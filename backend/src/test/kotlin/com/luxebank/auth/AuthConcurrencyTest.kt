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
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.post
import tools.jackson.databind.ObjectMapper
import java.util.concurrent.Callable
import java.util.concurrent.Executors

/** More concurrent logins than pooled connections must not starve the pool (each one writes audit rows). */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class AuthConcurrencyTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
) {
    @Test
    fun `concurrent failed and successful logins never exhaust the connection pool`() {
        val customers = (1..24).map { fixture.customer(withAccounts = false) }
        val pool = Executors.newFixedThreadPool(customers.size)
        val statuses =
            pool
                .invokeAll(
                    customers.mapIndexed { index, customer ->
                        Callable { login(customer, pin = if (index % 2 == 0) "111222" else BankFixture.PIN) }
                    },
                ).map { it.get() }
        pool.shutdown()

        assertThat(statuses.filterIndexed { index, _ -> index % 2 == 0 }).containsOnly(401)
        assertThat(statuses.filterIndexed { index, _ -> index % 2 == 1 }).containsOnly(200)
    }

    private fun login(
        customer: BankFixture.Customer,
        pin: String,
    ): Int {
        val challenge =
            objectMapper
                .readTree(
                    mockMvc
                        .post("/api/v1/auth/challenge") {
                            contentType = MediaType.APPLICATION_JSON
                            content = objectMapper.writeValueAsString(mapOf("deviceId" to customer.deviceId))
                        }.andReturn()
                        .response.contentAsString,
                )["challenge"]
                .asString()
        val body =
            mapOf(
                "deviceId" to customer.deviceId,
                "challenge" to challenge,
                "signature" to customer.deviceKey.signBase64(challenge),
                "method" to "PIN",
                "pin" to pin,
            )
        return mockMvc
            .post("/api/v1/auth/login") {
                contentType = MediaType.APPLICATION_JSON
                content = objectMapper.writeValueAsString(body)
            }.andReturn()
            .response.status
    }
}
