package com.luxebank.payments

/**
 * Slip-verification mini QR in the Thai banking format: tag 00 holds the API id, the sending
 * bank and the transaction reference; 51 is the country; 91 is a CRC-16/CCITT-FALSE over the rest.
 * LuxeBank uses the placeholder sending-bank code 099 until it has an ITMX member code.
 */
object SlipQr {
    private const val API_ID = "000001"
    private const val SENDING_BANK = "099"

    fun payload(reference: String): String {
        val inner = tlv("00", API_ID) + tlv("01", SENDING_BANK) + tlv("02", reference)
        val body = tlv("00", inner) + tlv("51", "TH") + "9104"
        return body + ThaiQr.crc(body)
    }

    fun tlv(
        tag: String,
        value: String,
    ): String = tag + value.length.toString().padStart(2, '0') + value
}
