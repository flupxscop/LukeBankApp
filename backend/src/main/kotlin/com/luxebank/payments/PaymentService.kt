package com.luxebank.payments

import com.luxebank.accounts.AccountRow
import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.ledger.Money
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

data class PartyResponse(
    val name: String,
    val bankCode: String?,
    val bankName: String?,
    val account: String?,
)

data class BillInfo(
    val billerCode: String,
    val billerName: String,
    val ref1: String,
    val ref2: String?,
    val customerName: String,
    val dueDate: LocalDate?,
)

data class InquiryResponse(
    val inquiryId: UUID,
    /** The device signs this single-use value to confirm (TRF-07). */
    val challenge: String,
    val expiresAt: Instant,
    val recipientType: String,
    val amount: String,
    val fee: String,
    val memo: String?,
    val from: PartyResponse,
    val to: PartyResponse,
    val requiresBiometric: Boolean,
    val bill: BillInfo?,
)

data class PaymentSlip(
    val transactionId: UUID,
    val referenceNo: String,
    val recipientType: String,
    val occurredAt: Instant,
    val amount: String,
    val fee: String,
    val memo: String?,
    val from: PartyResponse,
    val to: PartyResponse,
    /** Thai bank slip-verification mini QR (spec TRF-10). */
    val slipQr: String,
    val bill: BillInfo?,
)

data class LimitResponse(
    val dailyLimit: String,
    val usedToday: String,
    val remaining: String,
)

/** Everything an inquiry needs except its id, challenge and expiry. */
data class InquiryDraft(
    val kind: PaymentKind,
    val recipientType: RecipientType,
    val from: AccountRow,
    val toAccountId: UUID? = null,
    val bankCode: String? = null,
    val accountOrProxy: String? = null,
    val recipientName: String,
    val billerCode: String? = null,
    val ref1: String? = null,
    val ref2: String? = null,
    val amountSatang: Long,
    val memo: String? = null,
    val dueDate: LocalDate? = null,
)

data class ConfirmOptions(
    val saveAsFavorite: Boolean = false,
    val saveBill: Boolean = false,
)

data class ConfirmCommand(
    val kind: PaymentKind,
    val inquiryId: UUID,
    val idempotencyKey: String,
    val proof: PaymentProof,
    val options: ConfirmOptions,
)

/**
 * Inquiry → confirm for transfers and bills (spec 10.2). The inquiry fixes amount and recipient for
 * five minutes; confirmation only references it, so values cannot change in between (13.4.4).
 * A repeated Idempotency-Key returns the original slip instead of paying twice (TRF-14).
 */
@Service
class PaymentService(
    private val store: PaymentStore,
    private val executor: PaymentExecutor,
    private val authorizer: PaymentAuthorizer,
    private val billers: BillerCatalog,
    private val hasher: SecretHasher,
    private val audit: AuditService,
    private val clock: Clock,
) {
    @Transactional
    fun createInquiry(
        current: CurrentDevice,
        draft: InquiryDraft,
        english: Boolean,
    ): InquiryResponse {
        if (draft.amountSatang > draft.from.balanceSatang) throw ApiException(ErrorCode.INSUFFICIENT_FUNDS, "Insufficient funds")
        if (draft.kind == PaymentKind.TRANSFER && draft.recipientType != RecipientType.OWN) {
            executor.checkDailyLimit(draft.from, draft.amountSatang)
        }
        val inquiry =
            Inquiry(
                id = UUID.randomUUID(),
                userId = current.userId,
                deviceId = current.deviceId,
                kind = draft.kind,
                recipientType = draft.recipientType,
                fromAccountId = draft.from.id,
                toAccountId = draft.toAccountId,
                bankCode = draft.bankCode,
                accountOrProxy = draft.accountOrProxy,
                recipientName = draft.recipientName,
                billerCode = draft.billerCode,
                ref1 = draft.ref1,
                ref2 = draft.ref2,
                amountSatang = draft.amountSatang,
                feeSatang = 0,
                memo = draft.memo,
                challenge = hasher.randomToken(),
                requiresBiometric = draft.amountSatang >= STEP_UP_SATANG,
                expiresAt = Instant.now(clock).plus(INQUIRY_TTL),
                consumedAt = null,
            )
        store.insert(inquiry)
        return InquiryResponse(
            inquiryId = inquiry.id,
            challenge = inquiry.challenge,
            expiresAt = inquiry.expiresAt,
            recipientType = inquiry.recipientType.code,
            amount = Money.format(inquiry.amountSatang),
            fee = Money.format(inquiry.feeSatang),
            memo = inquiry.memo,
            from = PartyResponse(draft.from.name, Bank.LUXE.code, Bank.LUXE.name(english), Masking.account(draft.from.accountNumber)),
            to = recipientParty(inquiry, english),
            requiresBiometric = inquiry.requiresBiometric,
            bill = billInfo(inquiry, english, draft.dueDate),
        )
    }

    /**
     * Deliberately not one transaction: the authorizer and the audit trail each need their own connection,
     * and holding the payment's connection while waiting for another exhausts the pool under load.
     * Only [PaymentExecutor.execute] moves money, in a single transaction.
     */
    fun confirm(
        current: CurrentDevice,
        command: ConfirmCommand,
        english: Boolean,
    ): PaymentSlip {
        val idempotencyHash = hasher.tokenHash("${current.userId}:${command.idempotencyKey}")
        store.findByIdempotency(idempotencyHash)?.let { previous ->
            if (previous.inquiryId != command.inquiryId) throw duplicate()
            return slip(current.userId, previous.transactionId, english)
        }

        val inquiry = pendingInquiry(current, command)
        authorizer.authorize(current, inquiry.challenge, command.proof, inquiry.requiresBiometric)

        val transactionId =
            try {
                executor.execute(inquiry, idempotencyHash, command.options, english)
            } catch (error: ApiException) {
                audit.record(
                    AuditAction.PAYMENT_FAILED,
                    current.userId,
                    current.deviceId,
                    mapOf("inquiryId" to inquiry.id.toString(), "code" to error.code.name),
                )
                throw error
            }

        audit.record(
            AuditAction.PAYMENT_SUCCEEDED,
            current.userId,
            current.deviceId,
            mapOf(
                "inquiryId" to inquiry.id.toString(),
                "kind" to inquiry.recipientType.code,
                "amountSatang" to inquiry.amountSatang,
                "method" to command.proof.method.name,
            ),
        )
        return slip(current.userId, transactionId, english)
    }

    @Transactional(readOnly = true)
    fun slip(
        userId: UUID,
        transactionId: UUID,
        english: Boolean,
    ): PaymentSlip {
        val row = store.slipRow(userId, transactionId) ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        val inquiry = row.inquiry
        return PaymentSlip(
            transactionId = transactionId,
            referenceNo = row.referenceNo,
            recipientType = inquiry.recipientType.code,
            occurredAt = row.occurredAt,
            amount = Money.format(inquiry.amountSatang),
            fee = Money.format(inquiry.feeSatang),
            memo = inquiry.memo,
            from =
                PartyResponse(
                    Masking.name(if (english) row.payerEn else row.payerTh),
                    Bank.LUXE.code,
                    Bank.LUXE.name(english),
                    Masking.account(row.fromAccountNumber),
                ),
            to = recipientParty(inquiry, english),
            slipQr = SlipQr.payload(row.referenceNo),
            bill = billInfo(inquiry, english, null),
        )
    }

    @Transactional(readOnly = true)
    fun limits(account: AccountRow): LimitResponse {
        val used = store.transferredToday(account.id, LocalDate.now(clock))
        return LimitResponse(
            Money.format(account.dailyTransferLimitSatang),
            Money.format(used),
            Money.format((account.dailyTransferLimitSatang - used).coerceAtLeast(0)),
        )
    }

    private fun pendingInquiry(
        current: CurrentDevice,
        command: ConfirmCommand,
    ): Inquiry {
        val inquiry =
            store.findOwned(command.inquiryId, current.userId, current.deviceId)?.takeIf { it.kind == command.kind }
                ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        if (inquiry.consumedAt != null) throw duplicate()
        if (!inquiry.expiresAt.isAfter(
                Instant.now(clock),
            )
        ) {
            throw ApiException(ErrorCode.INQUIRY_EXPIRED, "This confirmation expired, start again")
        }
        return inquiry
    }

    private fun recipientParty(
        inquiry: Inquiry,
        english: Boolean,
    ): PartyResponse =
        when (inquiry.recipientType) {
            RecipientType.OWN ->
                PartyResponse(inquiry.recipientName, Bank.LUXE.code, Bank.LUXE.name(english), inquiry.accountOrProxy?.let(Masking::account))
            RecipientType.BILL -> {
                val biller = billers.require(checkNotNull(inquiry.billerCode))
                PartyResponse(biller.name(english), null, null, inquiry.ref1?.let(Masking::account))
            }
            else -> {
                val bank = Bank.of(inquiry.bankCode)
                PartyResponse(
                    Masking.name(inquiry.recipientName),
                    bank?.code,
                    bank?.name(english),
                    inquiry.accountOrProxy?.let(Masking::account),
                )
            }
        }

    private fun billInfo(
        inquiry: Inquiry,
        english: Boolean,
        dueDate: LocalDate?,
    ): BillInfo? {
        if (inquiry.kind != PaymentKind.BILL) return null
        val biller = billers.require(checkNotNull(inquiry.billerCode))
        return BillInfo(
            biller.code,
            biller.name(english),
            checkNotNull(inquiry.ref1),
            inquiry.ref2,
            Masking.name(inquiry.recipientName),
            dueDate,
        )
    }

    private fun duplicate() = ApiException(ErrorCode.DUPLICATE_REQUEST, "This payment was already submitted")

    companion object {
        /** TRF-09: from 50,000 baht a payment needs Face ID (D7). */
        const val STEP_UP_SATANG = 5_000_000L
        val INQUIRY_TTL: Duration = Duration.ofMinutes(5)
    }
}
