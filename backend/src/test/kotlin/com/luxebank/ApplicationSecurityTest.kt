package com.luxebank

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get

@SpringBootTest
@AutoConfigureMockMvc
@Import(TestcontainersConfiguration::class)
class ApplicationSecurityTest(
    @Autowired private val mockMvc: MockMvc,
) {
    @Test
    fun `health endpoint is public and hides details`() {
        mockMvc.get("/actuator/health").andExpect {
            status { isOk() }
            jsonPath("$.status") { value("UP") }
            jsonPath("$.components") { doesNotExist() }
        }
    }

    @Test
    fun `unknown endpoints are denied by default with the shared error format`() {
        mockMvc.get("/api/v1/accounts").andExpect {
            status { isUnauthorized() }
            jsonPath("$.error.code") { value("UNAUTHORIZED") }
            jsonPath("$.error.traceId") { exists() }
        }
    }

    @Test
    fun `other actuator endpoints are not exposed`() {
        mockMvc.get("/actuator/env").andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `responses carry security headers`() {
        mockMvc.get("/actuator/health").andExpect {
            header { string("X-Content-Type-Options", "nosniff") }
            header { string("X-Frame-Options", "DENY") }
            header { string("Referrer-Policy", "no-referrer") }
            header { exists("Content-Security-Policy") }
        }
    }

    @Test
    fun `safe trace id is echoed and unsafe one is replaced`() {
        mockMvc.get("/actuator/health") { header("X-Trace-Id", "abc12345-trace") }.andExpect {
            header { string("X-Trace-Id", "abc12345-trace") }
        }
        mockMvc.get("/actuator/health") { header("X-Trace-Id", "bad\nvalue") }.andExpect {
            header { exists("X-Trace-Id") }
            header { doesNotExist("X-Unexpected") }
        }
    }
}
