package com.luxebank.payments

import com.luxebank.accounts.AccountQueries
import com.luxebank.accounts.AccountRow
import com.luxebank.auth.CitizenId
import com.luxebank.auth.CurrentDevice
import com.luxebank.auth.LoginMethod
import com.luxebank.cards.CardStore
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecurityProperties
import com.luxebank.integration.BillPaymentGateway
import com.luxebank.integration.InterbankTransferGateway
import com.luxebank.integration.PromptPayDirectory
import com.luxebank.ledger.Money
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Clock
import java.time.Duration
import java.time.LocalDate
import java.time.YearMonth
import java.util.UUID

private const val MEMO_PATTERN = "^[^\\p{Cntrl}]*$"
private const val IDEMPOTENCY_PATTERN = "^[A-Za-z0-9-]{16,64}$"

data class RecipientRequest(
    /** own · internal · other_bank · promptpay · payee */
    @field:NotBlank val type: String,
    val accountId: UUID? = null,
    @field:Size(max = 8) val bankCode: String? = null,
    @field:Size(max = 20) val accountNumber: String? = null,
    @field:Size(max = 20) val proxy: String? = null,
    val payeeId: UUID? = null,
)

data class TransferInquiryRequest(
    val fromAccountId: UUID,
    @field:Valid val recipient: RecipientRequest,
    @field:Size(max = 16) val amount: String,
    @field:Size(max = 100) @field:Pattern(regexp = MEMO_PATTERN) val memo: String? = null,
)

data class ConfirmRequest(
    val inquiryId: UUID,
    val method: LoginMethod,
    @field:Size(max = 200) val signature: String,
    @field:Size(max = 6) val pin: String? = null,
    val saveAsFavorite: Boolean = false,
    val saveBill: Boolean = false,
)

data class BillInquiryRequest(
    val fromAccountId: UUID,
    @field:Size(max = 16) val billerCode: String? = null,
    @field:Size(max = 32) @field:Pattern(regexp = "^[A-Za-z0-9]*$") val ref1: String? = null,
    @field:Size(max = 32) @field:Pattern(regexp = "^[A-Za-z0-9]*$") val ref2: String? = null,
    val savedBillId: UUID? = null,
    /** Pay one of the customer's own LuxeBank credit cards (design "ชำระบัตร"). */
    val cardId: UUID? = null,
    @field:Size(max = 16) val amount: String? = null,
    @field:Size(max = 100) @field:Pattern(regexp = MEMO_PATTERN) val memo: String? = null,
)

data class QrRequest(
    @field:Size(max = 512) val payload: String,
)

data class QrResponse(
    val type: String,
    val proxy: String?,
    val billerCode: String?,
    val billerName: String?,
    val ref1: String?,
    val ref2: String?,
    val amount: String?,
    val merchantName: String?,
    val amountLocked: Boolean,
)

data class BillerResponse(
    val code: String,
    val name: String,
    val category: String,
    val ref1Label: String,
    val ref2Label: String?,
    val topUp: Boolean,
    val monogram: String,
    val partialPayment: Boolean,
) {
    companion object {
        fun of(
            biller: Biller,
            english: Boolean,
        ) = BillerResponse(
            biller.code,
            biller.name(english),
            biller.category,
            if (english) biller.ref1LabelEn else biller.ref1LabelTh,
            if (english) biller.ref2LabelEn else biller.ref2LabelTh,
            biller.topUp,
            biller.monogram,
            biller.partialPayment,
        )
    }
}

data class SavedBillResponse(
    val id: UUID,
    val biller: BillerResponse,
    val ref1: String,
    val nickname: String?,
    val amountDue: String?,
    val dueDate: LocalDate?,
    val paid: Boolean,
)

/** Turns a recipient request into a name-checked inquiry draft (TRF-01…05). */
@Service
class RecipientResolver(
    private val accounts: AccountQueries,
    private val payees: PayeeStore,
    private val interbank: InterbankTransferGateway,
    private val promptPay: PromptPayDirectory,
    private val redis: StringRedisTemplate,
    private val properties: SecurityProperties,
    private val clock: Clock,
) {
    fun transfer(
        current: CurrentDevice,
        request: TransferInquiryRequest,
        english: Boolean,
    ): InquiryDraft {
        throttle(current)
        val from = accounts.requireOwned(current.userId, request.fromAccountId)
        val amount = Money.parsePositive(request.amount) ?: invalid()
        val memo = request.memo?.trim()?.ifEmpty { null }
        val base = InquiryDraft(PaymentKind.TRANSFER, RecipientType.OWN, from, recipientName = "", amountSatang = amount, memo = memo)
        val recipient = request.recipient
        return when (recipient.type) {
            "own" -> own(base, current, recipient.accountId ?: invalid())
            "internal" -> internal(base, current, digits(recipient.accountNumber, ACCOUNT_DIGITS..ACCOUNT_DIGITS), english)
            "other_bank" -> otherBank(base, recipient.bankCode, digits(recipient.accountNumber, ACCOUNT_DIGITS..MAX_ACCOUNT_DIGITS))
            "promptpay" -> promptPay(base, recipient.proxy ?: invalid())
            "payee" -> payee(base, current, recipient.payeeId ?: invalid(), english)
            else -> invalid()
        }
    }

    private fun payee(
        base: InquiryDraft,
        current: CurrentDevice,
        payeeId: UUID,
        english: Boolean,
    ): InquiryDraft {
        val payee = payees.findOwned(current.userId, payeeId) ?: throw notFound()
        return when (payee.type) {
            RecipientType.INTERNAL -> internal(base, current, payee.accountOrProxy, english)
            RecipientType.OTHER_BANK -> otherBank(base, payee.bankCode, payee.accountOrProxy)
            else -> promptPay(base, payee.accountOrProxy)
        }
    }

    private fun own(
        base: InquiryDraft,
        current: CurrentDevice,
        accountId: UUID,
    ): InquiryDraft {
        val to = accounts.requireOwned(current.userId, accountId)
        if (to.id == base.from.id) invalid()
        return base.copy(recipientType = RecipientType.OWN, toAccountId = to.id, accountOrProxy = to.accountNumber, recipientName = to.name)
    }

    private fun internal(
        base: InquiryDraft,
        current: CurrentDevice,
        number: String,
        english: Boolean,
    ): InquiryDraft {
        val to: AccountRow = accounts.findActiveByNumber(number) ?: throw recipientNotFound()
        if (to.userId == current.userId) return own(base, current, to.id)
        return base.copy(
            recipientType = RecipientType.INTERNAL,
            toAccountId = to.id,
            bankCode = Bank.LUXE.code,
            accountOrProxy = to.accountNumber,
            recipientName = accounts.ownerName(to.userId, english),
        )
    }

    private fun otherBank(
        base: InquiryDraft,
        bankCode: String?,
        number: String,
    ): InquiryDraft {
        val bank = Bank.of(bankCode)?.takeIf { it != Bank.LUXE } ?: invalid()
        val account = interbank.lookup(bank.code, number) ?: throw recipientNotFound()
        return base.copy(
            recipientType = RecipientType.OTHER_BANK,
            bankCode = bank.code,
            accountOrProxy = number,
            recipientName = account.fullName,
        )
    }

    private fun promptPay(
        base: InquiryDraft,
        raw: String,
    ): InquiryDraft {
        val proxy = normalizeProxy(raw) ?: invalid()
        val account = promptPay.resolve(proxy) ?: throw recipientNotFound()
        return base.copy(
            recipientType = RecipientType.PROMPTPAY,
            bankCode = account.bankCode,
            accountOrProxy = proxy,
            recipientName = account.fullName,
        )
    }

    /** Mobile 0XXXXXXXXX, national ID with a valid checksum, or a 15-digit e-wallet ID. */
    private fun normalizeProxy(raw: String): String? {
        val digits = raw.filter(Char::isDigit)
        if (raw.any { !it.isDigit() && it != '-' && it != ' ' }) return null
        return when {
            digits.length == MOBILE_DIGITS && digits.startsWith("0") -> digits
            digits.length == CITIZEN_DIGITS -> CitizenId.normalize(digits)
            digits.length == EWALLET_DIGITS -> digits
            else -> null
        }
    }

    /** Per-customer cap on name inquiries so the directory cannot be enumerated (API6). */
    fun throttle(current: CurrentDevice) {
        val key = "inq:${current.userId}:${clock.millis() / MINUTE_MS}"
        val count = redis.opsForValue().increment(key) ?: 0
        if (count == 1L) redis.expire(key, Duration.ofMinutes(2))
        if (count >
            properties.limits.paymentInquiriesPerMinute
        ) {
            throw ApiException(ErrorCode.RATE_LIMITED, "Too many requests, wait a moment")
        }
    }

    private fun digits(
        value: String?,
        length: IntRange,
    ): String {
        val text = value ?: invalid()
        if (text.any { !it.isDigit() && it != '-' && it != ' ' }) invalid()
        return text.filter(Char::isDigit).takeIf { it.length in length } ?: invalid()
    }

    private fun recipientNotFound() = ApiException(ErrorCode.RECIPIENT_NOT_FOUND, "Recipient not found, check the details")

    private fun notFound() = ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    private fun invalid(): Nothing = throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    private companion object {
        const val ACCOUNT_DIGITS = 10
        const val MAX_ACCOUNT_DIGITS = 12
        const val MOBILE_DIGITS = 10
        const val CITIZEN_DIGITS = 13
        const val EWALLET_DIGITS = 15
        const val MINUTE_MS = 60_000L
    }
}

@RestController
@RequestMapping("/api/v1")
class TransfersController(
    private val resolver: RecipientResolver,
    private val payments: PaymentService,
    private val accounts: AccountQueries,
) {
    @GetMapping("/transfers/limits")
    fun limits(
        current: CurrentDevice,
        @RequestParam(required = false) accountId: UUID?,
    ): LimitResponse {
        val account = accountId?.let { accounts.requireOwned(current.userId, it) } ?: accounts.requirePrimary(current.userId)
        return payments.limits(account)
    }

    @PostMapping("/transfers/inquiry")
    fun inquiry(
        current: CurrentDevice,
        @Valid @RequestBody request: TransferInquiryRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): InquiryResponse = payments.createInquiry(current, resolver.transfer(current, request, language.isEnglish()), language.isEnglish())

    @PostMapping("/transfers")
    fun confirm(
        current: CurrentDevice,
        @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) idempotencyKey: String,
        @Valid @RequestBody request: ConfirmRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): PaymentSlip = payments.confirm(current, request.command(PaymentKind.TRANSFER, idempotencyKey), language.isEnglish())

    @GetMapping("/transactions/{id}/slip")
    fun slip(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): PaymentSlip = payments.slip(current.userId, id, language.isEnglish())
}

@RestController
@RequestMapping("/api/v1")
class BillsController(
    private val billers: BillerCatalog,
    private val gateway: BillPaymentGateway,
    private val resolver: RecipientResolver,
    private val payments: PaymentService,
    private val accounts: AccountQueries,
    private val cards: CardStore,
    private val clock: Clock,
) {
    @GetMapping("/billers")
    fun billers(
        @RequestParam(required = false) @Pattern(regexp = "^[a-z_]{1,16}$") category: String?,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): List<BillerResponse> = billers.list(category).map { BillerResponse.of(it, language.isEnglish()) }

    @PostMapping("/bills/inquiry")
    fun inquiry(
        current: CurrentDevice,
        @Valid @RequestBody request: BillInquiryRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): InquiryResponse {
        resolver.throttle(current)
        val english = language.isEnglish()
        val from = accounts.requireOwned(current.userId, request.fromAccountId)
        request.cardId?.let { return payments.createInquiry(current, cardPayment(current, from, it, request), english) }
        val saved = request.savedBillId?.let { billers.findSaved(current.userId, it) ?: throw notFound() }
        val biller = billers.find(saved?.billerCode ?: request.billerCode ?: invalid()) ?: throw notFound()
        val ref1 = saved?.ref1 ?: request.ref1?.takeIf { it.isNotEmpty() } ?: invalid()
        val ref2 = (saved?.ref2 ?: request.ref2)?.ifEmpty { null }
        val details =
            gateway.inquire(biller.code, ref1, ref2) ?: throw ApiException(ErrorCode.BILL_NOT_FOUND, "Bill not found, check the reference")
        val amount = billAmount(biller, request.amount, details.amountDueSatang)
        val draft =
            InquiryDraft(
                kind = PaymentKind.BILL,
                recipientType = RecipientType.BILL,
                from = from,
                recipientName = details.customerName,
                billerCode = biller.code,
                ref1 = ref1,
                ref2 = ref2,
                amountSatang = amount,
                memo = request.memo?.trim()?.ifEmpty { null },
                dueDate = details.dueDate,
            )
        return payments.createInquiry(current, draft, english)
    }

    @PostMapping("/bills/payments")
    fun pay(
        current: CurrentDevice,
        @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) idempotencyKey: String,
        @Valid @RequestBody request: ConfirmRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): PaymentSlip = payments.confirm(current, request.command(PaymentKind.BILL, idempotencyKey), language.isEnglish())

    /** Saved bills with what is due now (BILL-03); `paid` once paid in the current month. */
    @GetMapping("/bills/saved")
    fun saved(
        current: CurrentDevice,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): List<SavedBillResponse> {
        val english = language.isEnglish()
        val monthStart = YearMonth.now(clock).atDay(1)
        return billers.saved(current.userId).mapNotNull { bill ->
            val biller = billers.find(bill.billerCode) ?: return@mapNotNull null
            val details = gateway.inquire(bill.billerCode, bill.ref1, bill.ref2.ifEmpty { null })
            val paid = billers.paidSince(current.userId, bill.billerCode, bill.ref1, monthStart)
            SavedBillResponse(
                id = bill.id,
                biller = BillerResponse.of(biller, english),
                ref1 = Masking.account(bill.ref1),
                nickname = bill.nickname,
                amountDue = details?.amountDueSatang?.takeIf { !paid }?.let(Money::format),
                dueDate = details?.dueDate,
                paid = paid,
            )
        }
    }

    @DeleteMapping("/bills/saved/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteSaved(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ) {
        if (!billers.deleteSaved(current.userId, id)) throw notFound()
    }

    @PostMapping("/qr/parse")
    fun parseQr(
        @Valid @RequestBody request: QrRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): QrResponse {
        val qr = ThaiQr.parse(request.payload)
        val biller = qr.billerId?.let { billers.findByQrId(it) }
        if (qr.type == ParsedQr.Type.BILL && biller == null) throw ApiException(ErrorCode.QR_INVALID, "This biller is not supported yet")
        return QrResponse(
            type = qr.type.name.lowercase(),
            proxy = qr.proxy,
            billerCode = biller?.code,
            billerName = biller?.name(language.isEnglish()),
            ref1 = qr.ref1,
            ref2 = qr.ref2,
            amount = qr.amountSatang?.let(Money::format),
            merchantName = qr.merchantName,
            amountLocked = qr.amountLocked,
        )
    }

    /** Paying a LuxeBank credit card: due = what is owed, any amount up to it (the card biller is part-payable). */
    private fun cardPayment(
        current: CurrentDevice,
        from: AccountRow,
        cardId: UUID,
        request: BillInquiryRequest,
    ): InquiryDraft {
        val card =
            cards.findOwned(current.userId, cardId)?.takeIf { it.isCredit && it.status in setOf("active", "frozen") } ?: throw notFound()
        val owed = (-card.accountBalanceSatang).coerceAtLeast(0)
        val biller = billers.find(CARD_BILLER) ?: throw notFound()
        return InquiryDraft(
            kind = PaymentKind.BILL,
            recipientType = RecipientType.BILL,
            from = from,
            toAccountId = card.accountId,
            recipientName = accounts.ownerName(current.userId, english = false),
            billerCode = biller.code,
            ref1 = card.last4,
            amountSatang = billAmount(biller, request.amount, owed),
            memo = request.memo?.trim()?.ifEmpty { null },
        )
    }

    /**
     * Top-ups take the amount the customer chose; part-payable bills take any amount up to what is due;
     * every other bill is paid exactly as due, so a utility cannot be under- or over-paid.
     */
    private fun billAmount(
        biller: Biller,
        requested: String?,
        due: Long?,
    ): Long {
        val amount = requested?.let { Money.parsePositive(it) ?: invalid() }
        return when {
            biller.topUp -> amount ?: invalid()
            due == null || due <= 0 -> invalid()
            amount == null -> due
            biller.partialPayment && amount <= due -> amount
            amount == due -> amount
            else -> invalid()
        }
    }

    private fun notFound() = ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    private fun invalid(): Nothing = throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    private companion object {
        const val CARD_BILLER = "LXCARD"
    }
}

private fun ConfirmRequest.command(
    kind: PaymentKind,
    idempotencyKey: String,
) = ConfirmCommand(
    kind,
    inquiryId,
    idempotencyKey,
    PaymentProof(method, signature, pin),
    ConfirmOptions(saveAsFavorite = saveAsFavorite, saveBill = saveBill),
)
