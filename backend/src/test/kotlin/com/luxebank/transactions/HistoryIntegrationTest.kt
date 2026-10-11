package com.luxebank.transactions

import com.luxebank.TestcontainersConfiguration
import com.luxebank.ledger.BankFixture
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockHttpServletRequestDsl
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActionsDsl
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import tools.jackson.databind.JsonNode
import tools.jackson.databind.ObjectMapper
import java.time.LocalDate
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class HistoryIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
) {
    private val today = LocalDate.now(BankTime.ZONE)

    @Test
    fun `accounts list only the customer's own accounts, primary first, with masked numbers`() {
        val customer = fixture.customer()
        fixture.customer() // someone else
        fixture.deposit(customer.primary, 482_545_075)

        val body = get("/api/v1/accounts", customer.accessToken).andExpect { status { isOk() } }.json()

        val ids = body.map<JsonNode, String> { it["id"].asString() }
        assertThat(ids).containsExactly(customer.primary.toString(), customer.savings.toString())
        assertThat(body[0]["balance"].asString()).isEqualTo("4825450.75")
        assertThat(body[0]["maskedNumber"].asString()).matches("•••• \\d{4}")
        assertThat(body[0]["primary"].asBoolean()).isTrue()
    }

    @Test
    fun `history pages with a cursor, newest first, without gaps or repeats`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 1_000_000, fixture.at(today.minusDays(30)))
        repeat(24) { fixture.spend(customer.primary, 100L + it, fixture.at(today.minusDays(it / 3L), hour = 8 + it % 3)) }

        val seen = mutableListOf<String>()
        var cursor: String? = null
        var pages = 0
        do {
            val page =
                get(
                    "/api/v1/accounts/${customer.primary}/transactions",
                    customer.accessToken,
                    "limit" to "10",
                    "cursor" to cursor,
                ).andExpect { status { isOk() } }.json()
            if (pages == 0) {
                assertThat(page["summary"]["moneyIn"].asString()).isEqualTo("10000.00")
                assertThat(page["summary"]["moneyOut"].asString()).isEqualTo("26.76")
            } else {
                assertThat(page["summary"].isNull).isTrue()
            }
            seen += page["items"].map<JsonNode, String> { it["id"].asString() }
            cursor = page["nextCursor"].takeUnless { it.isNull }?.asString()
            pages++
        } while (cursor != null)

        assertThat(pages).isEqualTo(3)
        assertThat(seen).doesNotHaveDuplicates().containsExactlyElementsOf(fixture.transactionIds(customer.primary).map { it.toString() })
    }

    @Test
    fun `filters by direction, category, text and date range`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 10_000_000, fixture.at(today.minusDays(40)), merchant = "Payroll")
        fixture.spend(customer.primary, 58_000, fixture.at(today), merchant = "Sarnies Bangkok", memo = "brunch")
        fixture.spend(customer.primary, 125_000, fixture.at(today.minusDays(5)), merchant = "BTS Rabbit", category = Category.TRANSPORT)
        fixture.spend(customer.primary, 2_850_000, fixture.at(today.minusDays(35)), merchant = "100% Rent_Co", category = Category.HOUSING)
        val path = "/api/v1/accounts/${customer.primary}/transactions"

        fun merchants(vararg params: Pair<String, String?>) =
            get(path, customer.accessToken, *params)
                .andExpect { status { isOk() } }
                .json()["items"]
                .map<JsonNode, String> { it["merchant"].asString() }

        assertThat(merchants("direction" to "in")).containsExactly("Payroll")
        assertThat(merchants("direction" to "out")).hasSize(3)
        assertThat(merchants("category" to "transport")).containsExactly("BTS Rabbit")
        assertThat(merchants("q" to "SARNIES")).containsExactly("Sarnies Bangkok")
        assertThat(merchants("q" to "brunch")).containsExactly("Sarnies Bangkok")
        assertThat(merchants("q" to "%")).containsExactly("100% Rent_Co")
        assertThat(merchants("q" to "_")).containsExactly("100% Rent_Co")
        assertThat(merchants("from" to today.minusDays(30).toString())).containsExactly("Sarnies Bangkok", "BTS Rabbit")
        assertThat(merchants("from" to today.minusDays(36).toString(), "to" to today.minusDays(1).toString()))
            .containsExactly("BTS Rabbit", "100% Rent_Co")
    }

    @Test
    fun `invalid query parameters are rejected with the shared error body`() {
        val customer = fixture.customer()
        val path = "/api/v1/accounts/${customer.primary}/transactions"
        listOf(
            "limit" to "0",
            "limit" to "51",
            "cursor" to "not-a-cursor",
            "category" to "casino",
            "direction" to "sideways",
            "from" to "2026-13-01",
            "q" to "x".repeat(51),
        ).forEach { param ->
            get(path, customer.accessToken, param).andExpect {
                status { isBadRequest() }
                jsonPath("$.error.code") { value("VALIDATION_FAILED") }
            }
        }
        get(path, customer.accessToken, "from" to today.toString(), "to" to today.minusDays(1).toString())
            .andExpect { status { isBadRequest() } }
    }

    @Test
    fun `another customer's accounts and transactions read as not found (BOLA)`() {
        val owner = fixture.customer()
        val intruder = fixture.customer()
        fixture.deposit(owner.primary, 10_000)
        val transactionId = fixture.transactionIds(owner.primary).first()

        get("/api/v1/accounts/${owner.primary}/transactions", intruder.accessToken).andExpect {
            status { isNotFound() }
            jsonPath("$.error.code") { value("NOT_FOUND") }
        }
        get("/api/v1/transactions/$transactionId", intruder.accessToken).andExpect { status { isNotFound() } }
        patch("/api/v1/transactions/$transactionId", intruder.accessToken, mapOf("memo" to "pwned")).andExpect { status { isNotFound() } }
        get("/api/v1/accounts/${UUID.randomUUID()}/transactions", owner.accessToken).andExpect { status { isNotFound() } }

        get("/api/v1/transactions/$transactionId", owner.accessToken).andExpect {
            status { isOk() }
            jsonPath("$.transaction.memo") { doesNotExist() }
        }
    }

    @Test
    fun `history endpoints need a valid access token`() {
        val customer = fixture.customer()
        mockMvc.get("/api/v1/accounts").andExpect { status { isUnauthorized() } }
        mockMvc.get("/api/v1/accounts/${customer.primary}/transactions").andExpect { status { isUnauthorized() } }
        get("/api/v1/dashboard", "not-a-jwt").andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `detail shows reference, status and masked account, and recategorising feeds insights`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 100_000)
        fixture.spend(customer.primary, 58_000, memo = "brunch")
        val id = fixture.transactionIds(customer.primary).first()

        val detail = get("/api/v1/transactions/$id", customer.accessToken).andExpect { status { isOk() } }.json()
        assertThat(detail["transaction"]["amount"].asString()).isEqualTo("-580.00")
        assertThat(detail["transaction"]["category"].asString()).isEqualTo("food")
        assertThat(detail["referenceNo"].asString()).matches("LX\\d{6}[A-Z2-9]{10}")
        assertThat(detail["status"].asString()).isEqualTo("posted")
        assertThat(detail["account"]["maskedNumber"].asString()).matches("•••• \\d{4}")

        val month = today.toString().take(7)
        assertThat(spent(customer.accessToken, month, "food")).isEqualTo("580.00")

        patch("/api/v1/transactions/$id", customer.accessToken, mapOf("category" to "shopping", "memo" to "  ของขวัญ  "))
            .andExpect {
                status { isOk() }
                jsonPath("$.transaction.category") { value("shopping") }
                jsonPath("$.transaction.memo") { value("ของขวัญ") }
            }
        assertThat(spent(customer.accessToken, month, "food")).isNull()
        assertThat(spent(customer.accessToken, month, "shopping")).isEqualTo("580.00")

        patch("/api/v1/transactions/$id", customer.accessToken, mapOf("clearMemo" to true))
            .andExpect { jsonPath("$.transaction.memo") { doesNotExist() } }
    }

    @Test
    fun `invalid updates are rejected`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 100)
        val id = fixture.transactionIds(customer.primary).first()

        listOf(
            mapOf("category" to "casino"),
            mapOf("memo" to "x".repeat(101)),
            mapOf("memo" to "line\nbreak"),
            emptyMap(),
        ).forEach { body ->
            patch("/api/v1/transactions/$id", customer.accessToken, body).andExpect { status { isBadRequest() } }
        }
    }

    private fun spent(
        token: String,
        month: String,
        category: String,
    ): String? =
        get("/api/v1/insights/spending", token, "month" to month)
            .andExpect { status { isOk() } }
            .json()["byCategory"]
            .firstOrNull { it["category"].asString() == category }
            ?.get("spent")
            ?.asString()

    private fun get(
        path: String,
        token: String,
        vararg params: Pair<String, String?>,
    ): ResultActionsDsl =
        mockMvc.get(path) {
            bearer(token)
            params.forEach { (key, value) -> if (value != null) param(key, value) }
        }

    private fun patch(
        path: String,
        token: String,
        body: Map<String, Any?>,
    ): ResultActionsDsl =
        mockMvc.patch(path) {
            bearer(token)
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(body)
        }

    private fun MockHttpServletRequestDsl.bearer(token: String) = header("Authorization", "Bearer $token")

    private fun ResultActionsDsl.json(): JsonNode = objectMapper.readTree(andReturn().response.contentAsString)
}
