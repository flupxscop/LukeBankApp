package com.luxebank.integration.stub

import com.luxebank.integration.OtpCodeGenerator
import com.luxebank.integration.OtpSender
import com.luxebank.integration.StubAdapter
import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

/** Logs instead of sending SMS. Never logs the code itself (spec 13.1 A09). */
@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["otp"], havingValue = "stub", matchIfMissing = true)
class StubOtpSender :
    OtpSender,
    StubAdapter {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun send(
        phone: String,
        code: String,
        reference: String,
    ) {
        log.info("Stub SMS: OTP ref {} sent to ***{}", reference, phone.takeLast(VISIBLE_DIGITS))
    }

    private companion object {
        const val VISIBLE_DIGITS = 4
    }
}

/** Fixed code 000000 for local development and tests (spec 7.0). */
@Component
@Profile("local", "test")
class FixedOtpCodeGenerator :
    OtpCodeGenerator,
    StubAdapter {
    override fun generate(): String = "000000"
}
