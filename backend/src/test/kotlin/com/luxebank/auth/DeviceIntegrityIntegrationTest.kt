package com.luxebank.auth

import com.luxebank.TestcontainersConfiguration
import com.luxebank.ledger.BankFixture
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class DeviceIntegrityIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val fixture: BankFixture,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
) {
    @Test
    fun `a compromised phone cannot move money or reveal cards but can still view and block`() {
        val customer = fixture.customer()
        val card = fixture.card(customer, credit = false)

        for (path in listOf("/api/v1/transfers", "/api/v1/bills/payments", "/api/v1/cards/$card/sensitive")) {
            mockMvc
                .post(path) {
                    header("Authorization", "Bearer ${customer.accessToken}")
                    header("X-Device-Integrity", "compromised")
                    header("Idempotency-Key", UUID.randomUUID().toString())
                    contentType = MediaType.APPLICATION_JSON
                    content = "{}"
                }.andExpect {
                    status { isForbidden() }
                    jsonPath("$.error.code") { value("DEVICE_COMPROMISED") }
                }
        }
        val blocked =
            jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_log WHERE action = 'DEVICE_INTEGRITY_BLOCKED' AND actor_id = :user",
                mapOf("user" to customer.userId),
                Long::class.java,
            )
        assertThat(blocked).isEqualTo(3)

        mockMvc
            .get("/api/v1/accounts") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("X-Device-Integrity", "compromised")
            }.andExpect { status { isOk() } }
        mockMvc
            .post("/api/v1/cards/$card/freeze") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("X-Device-Integrity", "compromised")
            }.andExpect { status { isOk() } }
    }

    @Test
    fun `the header is ignored unless it says compromised`() {
        val customer = fixture.customer()
        mockMvc
            .post("/api/v1/transfers") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("X-Device-Integrity", "ok")
                contentType = MediaType.APPLICATION_JSON
                content = "{}"
            }.andExpect { jsonPath("$.error.code") { value("VALIDATION_FAILED") } }
    }

    @Test
    fun `an anonymous request is still rejected as unauthenticated`() {
        mockMvc
            .post("/api/v1/transfers") {
                header("X-Device-Integrity", "compromised")
            }.andExpect { status { isUnauthorized() } }
    }
}
