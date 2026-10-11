package com.luxebank.payments

import com.luxebank.accounts.AccountQueries
import com.luxebank.accounts.AccountRow
import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.integration.BillPaymentGateway
import com.luxebank.integration.ExternalAccount
import com.luxebank.integration.InterbankTransferGateway
import com.luxebank.ledger.Category
import com.luxebank.ledger.Channel
import com.luxebank.ledger.EntryDetails
import com.luxebank.ledger.InternalAccounts
import com.luxebank.ledger.JournalType
import com.luxebank.ledger.LedgerService
import com.luxebank.ledger.Line
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
    private val accounts: AccountQueries,
    private val ledger: LedgerService,
    private val authorizer: PaymentAuthorizer,
    private val interbank: InterbankTransferGateway,
    private val bills: BillPaymentGateway,
    private val billers: BillerCatalog,
    private val payees: PayeeStore,
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
            checkDailyLimit(draft.from, draft.amountSatang)
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

    @Transactional
    fun confirm(
        current: CurrentDevice,
        command: ConfirmCommand,
        english: Boolean,
    ): PaymentSlip {
        val proof = command.proof
        val options = command.options
        val idempotencyHash = hasher.tokenHash("${current.userId}:${command.idempotencyKey}")
        store.findByIdempotency(idempotencyHash)?.let { previous ->
            if (previous.inquiryId != command.inquiryId) throw duplicate()
            return slip(current.userId, previous.transactionId, english)
        }

        val inquiry = pendingInquiry(current, command)
        authorizer.authorize(current, inquiry.challenge, proof, inquiry.requiresBiometric)

        if (!store.consume(inquiry.id, Instant.now(clock))) throw duplicate()
        store.lockAccount(inquiry.fromAccountId)
        val from = accounts.requireOwned(current.userId, inquiry.fromAccountId)
        if (inquiry.kind == PaymentKind.TRANSFER && inquiry.recipientType != RecipientType.OWN) {
            checkDailyLimit(from, inquiry.amountSatang)
        }

        val entryId =
            try {
                post(inquiry, from, idempotencyHash, english)
            } catch (error: ApiException) {
                audit.record(
                    AuditAction.PAYMENT_FAILED,
                    current.userId,
                    current.deviceId,
                    mapOf("inquiryId" to inquiry.id.toString(), "code" to error.code.name),
                )
                throw error
            }
        val transactionId = store.payerTransaction(entryId, from.id)
        store.insertPayment(current.userId, inquiry.id, idempotencyHash, entryId, transactionId)

        if (inquiry.kind == PaymentKind.TRANSFER) payees.remember(inquiry, favorite = options.saveAsFavorite)
        if (options.saveBill && inquiry.kind == PaymentKind.BILL) billers.save(current.userId, inquiry)

        audit.record(
            AuditAction.PAYMENT_SUCCEEDED,
            current.userId,
            current.deviceId,
            mapOf(
                "inquiryId" to inquiry.id.toString(),
                "kind" to inquiry.recipientType.code,
                "amountSatang" to inquiry.amountSatang,
                "method" to proof.method.name,
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

    private fun post(
        inquiry: Inquiry,
        from: AccountRow,
        idempotencyHash: String,
        english: Boolean,
    ): UUID {
        val amount = inquiry.amountSatang
        val shownName = if (inquiry.recipientType == RecipientType.OWN) inquiry.recipientName else Masking.name(inquiry.recipientName)
        val channel = if (inquiry.recipientType == RecipientType.PROMPTPAY) Channel.PROMPTPAY else Channel.TRANSFER
        val debit = Line(from.id, -amount, EntryDetails(shownName, Category.TRANSFER, channel, memo = inquiry.memo))

        return when (inquiry.recipientType) {
            RecipientType.OWN, RecipientType.INTERNAL -> {
                val to = checkNotNull(inquiry.toAccountId)
                val credit =
                    if (inquiry.recipientType == RecipientType.OWN) {
                        EntryDetails(from.name, Category.TRANSFER, Channel.TRANSFER, memo = inquiry.memo)
                    } else {
                        EntryDetails(
                            Masking.name(payerName(inquiry.userId, english)),
                            Category.INCOME,
                            Channel.TRANSFER,
                            memo = inquiry.memo,
                        )
                    }
                ledger.post(JournalType.TRANSFER, listOf(debit, Line(to, amount, credit)), idempotencyKey = idempotencyHash)
            }
            RecipientType.OTHER_BANK, RecipientType.PROMPTPAY -> {
                val entry =
                    ledger.post(
                        JournalType.TRANSFER,
                        listOf(debit, Line(InternalAccounts.CLEARING, amount)),
                        idempotencyKey = idempotencyHash,
                    )
                val target = ExternalAccount(checkNotNull(inquiry.bankCode), checkNotNull(inquiry.accountOrProxy), inquiry.recipientName)
                // Inside the database transaction: a rejection rolls the debit back (production adds pending + reversal).
                interbank.transfer(target, amount, entry.toString())
                entry
            }
            RecipientType.BILL -> {
                val biller = billers.require(checkNotNull(inquiry.billerCode))
                val details = EntryDetails(biller.name(english), Category.BILLS, Channel.BILL, biller.monogram, inquiry.memo)
                val entry =
                    ledger.post(
                        JournalType.BILL,
                        listOf(Line(from.id, -amount, details), Line(InternalAccounts.CLEARING, amount)),
                        idempotencyKey = idempotencyHash,
                    )
                bills.pay(biller.code, checkNotNull(inquiry.ref1), inquiry.ref2, amount, entry.toString())
                entry
            }
        }
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

    private fun payerName(
        userId: UUID,
        english: Boolean,
    ): String = accounts.ownerName(userId, english)

    private fun checkDailyLimit(
        from: AccountRow,
        amount: Long,
    ) {
        val used = store.transferredToday(from.id, LocalDate.now(clock))
        if (used + amount > from.dailyTransferLimitSatang) {
            throw ApiException(ErrorCode.DAILY_LIMIT_EXCEEDED, "This transfer is over today's limit")
        }
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
