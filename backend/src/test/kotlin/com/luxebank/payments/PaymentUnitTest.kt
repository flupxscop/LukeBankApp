package com.luxebank.payments

import com.luxebank.common.error.ApiException
import com.luxebank.ledger.Money
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test

class PaymentUnitTest {
    @Test
    fun `amounts parse to satang and reject anything ambiguous`() {
        assertThat(Money.parsePositive("75000")).isEqualTo(7_500_000)
        assertThat(Money.parsePositive("0.5")).isEqualTo(50)
        assertThat(Money.parsePositive("1.05")).isEqualTo(105)
        listOf("0", "0.00", "-1", "1.001", "1,000", " 1", "1e3", "", ".5", "12345678901").forEach {
            assertThat(Money.parsePositive(it)).describedAs(it).isNull()
        }
    }

    @Test
    fun `names keep the title and first name, numbers keep four digits`() {
        assertThat(Masking.name("นาย สมชาย ใจดี")).isEqualTo("นาย สมชาย ใจ**")
        assertThat(Masking.name("นกน้อย ใจงาม")).isEqualTo("นกน้อย ใจ**")
        assertThat(Masking.name("Noknoi")).isEqualTo("Noknoi")
        assertThat(Masking.account("123-4-56789-0")).isEqualTo("x7890")
    }

    @Test
    fun `CRC matches the CCITT-FALSE check value`() {
        assertThat(ThaiQr.crc("123456789")).isEqualTo("29B1")
    }

    @Test
    fun `QR payloads with bad structure, currency or amount are rejected`() {
        fun signed(body: String) = (body + "6304").let { it + ThaiQr.crc(it) }
        val promptPay = SlipQr.tlv("29", SlipQr.tlv("00", "A000000677010111") + SlipQr.tlv("02", "1234567890121"))

        assertThat(ThaiQr.parse(signed(promptPay)).proxy).isEqualTo("1234567890121")
        listOf(
            signed(promptPay + SlipQr.tlv("53", "840")),
            signed(promptPay + SlipQr.tlv("54", "-5")),
            signed("2999" + "x"),
            signed(SlipQr.tlv("29", SlipQr.tlv("00", "A000000677010111") + SlipQr.tlv("01", "0812345678"))),
            signed(SlipQr.tlv("29", SlipQr.tlv("00", "B000000677010111") + SlipQr.tlv("02", "1234567890121"))),
            signed(SlipQr.tlv("58", "TH")),
            "x".repeat(600),
            "ไทย",
        ).forEach { payload ->
            assertThatThrownBy { ThaiQr.parse(payload) }.describedAs(payload).isInstanceOf(ApiException::class.java)
        }
    }
}
