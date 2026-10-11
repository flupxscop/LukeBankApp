package com.luxebank

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.extension.ExtendWith
import org.slf4j.LoggerFactory
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.system.CapturedOutput
import org.springframework.boot.test.system.OutputCaptureExtension
import org.springframework.context.annotation.Import
import org.springframework.test.context.ActiveProfiles

/** NFR-05 / spec 13.4.4: logs never carry full account, card or ID numbers or tokens. */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
@ExtendWith(OutputCaptureExtension::class)
class LogMaskingTest {
    private val log = LoggerFactory.getLogger(javaClass)

    @Test
    fun `numbers and tokens are masked in messages and stack traces`(output: CapturedOutput) {
        val pan = "4532017522868821"
        val account = "1234567890"
        val jwt = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl"

        log.info("Transfer from {} with card {} using {}", account, pan, jwt)
        log.error("Unhandled error", IllegalStateException("duplicate key (account_number)=($account)"))

        assertThat(output.out).contains("[masked]")
        assertThat(output.out).doesNotContain(pan, account, jwt)
        assertThat(output.out).contains("IllegalStateException")
        // Short numbers such as amounts, dates and line numbers stay readable.
        log.info("Paid 1500.00 on 2026-10-11")
        assertThat(output.out).contains("Paid 1500.00 on 2026-10-11")
    }
}
