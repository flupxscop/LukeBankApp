package com.luxebank.performance

import com.luxebank.TestcontainersConfiguration
import com.luxebank.ledger.BankFixture
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import tools.jackson.databind.ObjectMapper
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * NFR-02 budget check: p95 ≤ 500 ms for reads and ≤ 2 s for a transfer (inquiry + confirm), measured in-process
 * against PostgreSQL and Redis with a customer holding a year of history. Network time is not included, so this
 * guards against slow queries and lock contention; the production SLO is measured at the edge.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class PerformanceBudgetTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Test
    fun `reads and transfers stay within the NFR-02 budget`() {
        val customer = fixture.customer().also { fixture.deposit(it.primary, 500_000_000, at = Instant.now().minus(Duration.ofDays(366))) }
        repeat(HISTORY) { day ->
            val at = Instant.now().minus(Duration.ofHours(6L * (HISTORY - day)))
            fixture.spend(customer.primary, 1_000L + day, at = at, merchant = "Merchant ${day % 40}")
        }

        val dashboard = measure(READS) { get("/api/v1/dashboard", customer) }
        val history = measure(READS) { get("/api/v1/accounts/${customer.primary}/transactions?limit=20", customer) }
        // Inquiries are rate limited per customer (30/min, anti-enumeration), so transfers rotate across payers.
        val payers = List(PAYERS) { fixture.customer().also { fixture.deposit(it.primary, 10_000_000) } }
        var next = 0
        val transfer = measure(TRANSFERS) { transfer(payers[next++ % payers.size]) }

        // Data per screen on a mobile connection: the home screen and one history page stay small.
        val dashboardBytes = bytes("/api/v1/dashboard", customer)
        val historyBytes = bytes("/api/v1/accounts/${customer.primary}/transactions?limit=20", customer)

        log.info("NFR-02 p95: dashboard {} ms, history {} ms, transfer {} ms", dashboard, history, transfer)
        log.info("Payload: dashboard {} bytes, history page {} bytes", dashboardBytes, historyBytes)
        assertThat(dashboardBytes).isLessThan(DASHBOARD_PAYLOAD_BYTES)
        assertThat(historyBytes).isLessThan(HISTORY_PAYLOAD_BYTES)
        assertThat(dashboard).isLessThan(READ_BUDGET_MS)
        assertThat(history).isLessThan(READ_BUDGET_MS)
        assertThat(transfer).isLessThan(TRANSFER_BUDGET_MS)
    }

    /** p95 in milliseconds after a short warm-up. */
    private fun measure(
        count: Int,
        call: () -> Unit,
    ): Long {
        repeat(WARMUP) { call() }
        val samples =
            (1..count)
                .map {
                    val start = System.nanoTime()
                    call()
                    (System.nanoTime() - start) / NANOS_PER_MS
                }.sorted()
        return samples[(samples.size * P95 / PERCENT).coerceAtMost(samples.size - 1)]
    }

    private fun get(
        path: String,
        customer: BankFixture.Customer,
    ) {
        mockMvc.get(path) { header("Authorization", "Bearer ${customer.accessToken}") }.andExpect { status { isOk() } }
    }

    private fun bytes(
        path: String,
        customer: BankFixture.Customer,
    ): Int =
        mockMvc
            .get(path) { header("Authorization", "Bearer ${customer.accessToken}") }
            .andReturn()
            .response.contentAsByteArray.size

    private fun transfer(customer: BankFixture.Customer) {
        val inquiry =
            mockMvc
                .post("/api/v1/transfers/inquiry") {
                    header("Authorization", "Bearer ${customer.accessToken}")
                    contentType = MediaType.APPLICATION_JSON
                    content =
                        objectMapper.writeValueAsString(
                            mapOf(
                                "fromAccountId" to customer.primary,
                                "recipient" to mapOf("type" to "own", "accountId" to customer.savings),
                                "amount" to "10.00",
                            ),
                        )
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString
                .let(objectMapper::readTree)
        mockMvc
            .post("/api/v1/transfers") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("Idempotency-Key", UUID.randomUUID().toString())
                contentType = MediaType.APPLICATION_JSON
                content =
                    objectMapper.writeValueAsString(
                        mapOf(
                            "inquiryId" to inquiry["inquiryId"].asString(),
                            "method" to "PIN",
                            "pin" to BankFixture.PIN,
                            "signature" to customer.deviceKey.signBase64(inquiry["challenge"].asString()),
                        ),
                    )
            }.andExpect { status { isOk() } }
    }

    private companion object {
        const val HISTORY = 1_460
        const val WARMUP = 10
        const val READS = 100
        const val TRANSFERS = 40
        const val PAYERS = 5
        const val READ_BUDGET_MS = 500L
        const val TRANSFER_BUDGET_MS = 2_000L
        const val NANOS_PER_MS = 1_000_000L
        const val DASHBOARD_PAYLOAD_BYTES = 50 * 1024
        const val HISTORY_PAYLOAD_BYTES = 20 * 1024
        const val P95 = 95
        const val PERCENT = 100
    }
}
