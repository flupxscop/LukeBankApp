package com.luxebank.integration.stub

import com.luxebank.integration.CardProcessor
import com.luxebank.integration.CardRules
import com.luxebank.integration.CardSecrets
import com.luxebank.integration.IssuedCard
import com.luxebank.integration.StubAdapter
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Clock
import java.time.LocalDate
import java.util.HexFormat

/**
 * Simulated card processor. Card numbers and CVVs are derived from the token, so they are stable
 * across restarts without LuxeBank ever storing them; they pass the Luhn check but use test BINs.
 */
@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["cards"], havingValue = "stub", matchIfMissing = true)
class StubCardProcessor(
    private val clock: Clock,
) : CardProcessor,
    StubAdapter {
    private val random = SecureRandom()

    override fun issue(
        credit: Boolean,
        productName: String,
    ): IssuedCard {
        val bytes = ByteArray(TOKEN_BYTES).also(random::nextBytes)
        val token = (if (credit) "tokc_" else "tokd_") + HexFormat.of().formatHex(bytes)
        val expiry = LocalDate.now(clock).plusYears(VALID_YEARS)
        return IssuedCard(token, pan(token).takeLast(LAST4), expiry.monthValue, expiry.year)
    }

    override fun reveal(tokenRef: String): CardSecrets = CardSecrets(pan(tokenRef), digits(tokenRef + ":cvv", CVV_DIGITS))

    override fun applyRules(
        tokenRef: String,
        rules: CardRules,
    ) = Unit

    override fun block(tokenRef: String) = Unit

    /** 16-digit test PAN with a valid Luhn check digit. */
    private fun pan(token: String): String {
        val bin = if (token.startsWith("tokc_")) CREDIT_BIN else DEBIT_BIN
        val body = bin + digits(token, PAN_DIGITS - bin.length - 1)
        return body + luhnCheckDigit(body)
    }

    private fun digits(
        seed: String,
        count: Int,
    ): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
        return hash.take(count).joinToString("") { (Math.floorMod(it.toInt(), DECIMAL)).toString() }
    }

    private fun luhnCheckDigit(body: String): Int {
        val sum =
            body
                .reversed()
                .mapIndexed { index, char ->
                    val digit = char.digitToInt()
                    if (index % 2 == 0) (digit * 2).let { if (it > NINE) it - NINE else it } else digit
                }.sum()
        return (DECIMAL - sum % DECIMAL) % DECIMAL
    }

    private companion object {
        const val DEBIT_BIN = "453201"
        const val CREDIT_BIN = "552133"
        const val PAN_DIGITS = 16
        const val CVV_DIGITS = 3
        const val LAST4 = 4
        const val TOKEN_BYTES = 16
        const val VALID_YEARS = 5L
        const val DECIMAL = 10
        const val NINE = 9
    }
}
