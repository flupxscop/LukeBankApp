package com.luxebank.integration

/** Marker for development stand-ins of external systems (spec 7.0). */
interface StubAdapter

/** Sends the one-time code by SMS to the phone registered with the bank. */
interface OtpSender {
    fun send(
        phone: String,
        code: String,
        reference: String,
    )
}

/** Produces the six-digit one-time code. */
fun interface OtpCodeGenerator {
    fun generate(): String
}

/** A person or company at another bank, as the bank's directory reports them. */
data class ExternalAccount(
    val bankCode: String,
    val accountNumber: String,
    val fullName: String,
)

/** ITMX / partner bank: name inquiry and credit transfer to other banks (TRF-03). */
interface InterbankTransferGateway {
    /** Null when the account does not exist. */
    fun lookup(
        bankCode: String,
        accountNumber: String,
    ): ExternalAccount?

    /** Throws [com.luxebank.common.error.ApiException] with SERVICE_UNAVAILABLE when the other bank rejects or times out. */
    fun transfer(
        to: ExternalAccount,
        amountSatang: Long,
        reference: String,
    )
}

/** PromptPay proxy lookup by mobile number or national ID (TRF-04). */
fun interface PromptPayDirectory {
    /** Null when nobody registered the proxy. */
    fun resolve(proxy: String): ExternalAccount?
}

data class BillDetails(
    val customerName: String,
    /** Null for top-ups, where the customer picks the amount. */
    val amountDueSatang: Long?,
    val dueDate: java.time.LocalDate?,
)

/** Bill payment aggregator (BILL-01…05). */
interface BillPaymentGateway {
    /** Null when the reference is unknown to the biller. */
    fun inquire(
        billerCode: String,
        ref1: String,
        ref2: String?,
    ): BillDetails?

    fun pay(
        billerCode: String,
        ref1: String,
        ref2: String?,
        amountSatang: Long,
        reference: String,
    )
}

/** What the card processor returns when it issues a card; LuxeBank stores only these fields. */
data class IssuedCard(
    val tokenRef: String,
    val last4: String,
    val expiryMonth: Int,
    val expiryYear: Int,
)

/** Full card details, fetched from the processor only for a step-up-verified reveal (CARD-07). Never stored. */
data class CardSecrets(
    val pan: String,
    val cvv: String,
)

data class CardRules(
    val active: Boolean,
    val online: Boolean,
    val overseas: Boolean,
    val contactless: Boolean,
    val atm: Boolean,
    val dailyLimitSatang: Long,
)

/** Card processor (spec 7.0): issues cards, holds PAN/CVV and authorises purchases by the rules LuxeBank sets. */
interface CardProcessor {
    fun issue(
        credit: Boolean,
        productName: String,
    ): IssuedCard

    fun reveal(tokenRef: String): CardSecrets

    /** Pushes freeze state, channels and daily limit; the processor declines purchases that break them. */
    fun applyRules(
        tokenRef: String,
        rules: CardRules,
    )

    /** Permanently blocks a lost or stolen card. */
    fun block(tokenRef: String)
}
