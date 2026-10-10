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
