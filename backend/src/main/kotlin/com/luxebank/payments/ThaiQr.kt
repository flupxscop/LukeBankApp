package com.luxebank.payments

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.Money

/** What a scanned Thai QR asks the customer to pay (TRF-12, BILL-02). */
data class ParsedQr(
    val type: Type,
    /** PromptPay target, normalised: 0812345678, a 13-digit national ID or a 15-digit e-wallet ID. */
    val proxy: String? = null,
    val billerId: String? = null,
    val ref1: String? = null,
    val ref2: String? = null,
    /** Satang; null when the payer enters the amount (static QR). */
    val amountSatang: Long? = null,
    val merchantName: String? = null,
) {
    enum class Type { PROMPTPAY, BILL }
}

/**
 * EMVCo merchant-presented QR as used by Thai QR Payment: TLV fields (2-digit tag, 2-digit length),
 * PromptPay in tag 29, bill payment in tag 30, amount in 54, CRC-16/CCITT-FALSE in 63.
 * Anything malformed, unsigned or not in baht is rejected rather than guessed (13.1 A03).
 */
object ThaiQr {
    private const val PROMPTPAY_AID = "A000000677010111"
    private const val BILL_AID = "A000000677010112"
    private const val THB = "764"
    private const val MAX_LENGTH = 512
    private const val HEADER = 4
    private const val CRC_LENGTH = 4

    fun parse(payload: String): ParsedQr {
        val text = payload.trim()
        if (text.length > MAX_LENGTH || !text.matches(Regex("^[\\x20-\\x7E]+$"))) invalid()
        val crcStart = text.length - CRC_LENGTH
        if (crcStart < HEADER || text.substring(crcStart - HEADER, crcStart) != "6304") invalid()
        if (!crc(text.substring(0, crcStart)).equals(text.substring(crcStart), ignoreCase = true)) invalid()

        val fields = fields(text.substring(0, crcStart - HEADER))
        fields["53"]?.let { if (it != THB) invalid() }
        val amount = fields["54"]?.let { Money.parsePositive(it) ?: invalid() }
        val name = fields["59"]

        fields["29"]?.let { return promptPay(fields(it), amount, name) }
        fields["30"]?.let { return bill(fields(it), amount, name) }
        invalid()
    }

    private fun promptPay(
        sub: Map<String, String>,
        amount: Long?,
        name: String?,
    ): ParsedQr {
        if (sub["00"] != PROMPTPAY_AID) invalid()
        val proxy =
            sub["01"]?.let(::mobile)
                ?: sub["02"]?.takeIf { it.matches(Regex("^\\d{13}$")) }
                ?: sub["03"]?.takeIf { it.matches(Regex("^\\d{15}$")) }
                ?: invalid()
        return ParsedQr(ParsedQr.Type.PROMPTPAY, proxy = proxy, amountSatang = amount, merchantName = name)
    }

    private fun bill(
        sub: Map<String, String>,
        amount: Long?,
        name: String?,
    ): ParsedQr {
        if (sub["00"] != BILL_AID) invalid()
        val billerId = sub["01"]?.takeIf { it.matches(Regex("^\\d{15}$")) } ?: invalid()
        val ref1 = sub["02"]?.takeIf { it.isNotBlank() } ?: invalid()
        return ParsedQr(ParsedQr.Type.BILL, billerId = billerId, ref1 = ref1, ref2 = sub["03"], amountSatang = amount, merchantName = name)
    }

    /** CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) as four upper-case hex digits. */
    fun crc(data: String): String {
        var crc = CRC_INIT
        for (byte in data.toByteArray(Charsets.US_ASCII)) {
            crc = crc xor ((byte.toInt() and BYTE_MASK) shl BYTE_BITS)
            repeat(BYTE_BITS) {
                crc = if (crc and HIGH_BIT != 0) (crc shl 1) xor POLY else crc shl 1
                crc = crc and WORD_MASK
            }
        }
        return "%04X".format(crc)
    }

    /** "0066812345678" → "0812345678". */
    private fun mobile(value: String): String? {
        if (!value.matches(Regex("^0066\\d{9}$"))) return null
        return "0" + value.removePrefix("0066")
    }

    private fun fields(data: String): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        var index = 0
        while (index < data.length) {
            if (index + HEADER > data.length) invalid()
            val tag = data.substring(index, index + 2)
            val length = data.substring(index + 2, index + HEADER).toIntOrNull() ?: invalid()
            val end = index + HEADER + length
            if (end > data.length) invalid()
            result[tag] = data.substring(index + HEADER, end)
            index = end
        }
        return result
    }

    private fun invalid(): Nothing = throw ApiException(ErrorCode.QR_INVALID, "This QR code is not a valid Thai QR payment")

    private const val CRC_INIT = 0xFFFF
    private const val POLY = 0x1021
    private const val HIGH_BIT = 0x8000
    private const val WORD_MASK = 0xFFFF
    private const val BYTE_MASK = 0xFF
    private const val BYTE_BITS = 8
}
