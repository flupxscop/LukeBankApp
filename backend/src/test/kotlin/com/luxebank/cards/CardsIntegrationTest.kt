package com.luxebank.cards

import com.luxebank.TestcontainersConfiguration
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.BankFixture
import com.luxebank.ledger.BankTime
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActionsDsl
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post
import tools.jackson.databind.JsonNode
import tools.jackson.databind.ObjectMapper
import java.time.LocalDate
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class CardsIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
) {
    @Test
    fun `cards list shows debit and credit with a simulated statement`() {
        val customer = fixture.customer().also { fixture.deposit(it.primary, 100_000) }
        val debit = fixture.card(customer, credit = false)
        val credit = fixture.card(customer, credit = true, rewardPoints = 12_800)
        listOf(58_000L, 2_450_000, 3_890_000, 412_000, 1_640_000, 192_000).forEach { fixture.purchase(credit, it) }

        val cards = get("/api/v1/cards", customer).andExpect { status { isOk() } }.json()
        assertThat(cards.map<JsonNode, String> { it["id"].asString() }).containsExactlyInAnyOrder(debit.toString(), credit.toString())

        val creditCard = cards.first { it["id"].asString() == credit.toString() }
        assertThat(creditCard["credit"]["limit"].asString()).isEqualTo("500000.00")
        assertThat(creditCard["credit"]["used"].asString()).isEqualTo("86420.00")
        assertThat(creditCard["credit"]["available"].asString()).isEqualTo("413580.00")
        assertThat(creditCard["credit"]["minimumPayment"].asString()).isEqualTo("8642.00")
        val nextMonth = LocalDate.now(BankTime.ZONE).plusMonths(1).withDayOfMonth(2)
        assertThat(creditCard["credit"]["dueDate"].asString()).isEqualTo(nextMonth.toString())
        assertThat(creditCard["rewardPoints"].asLong()).isEqualTo(12_800)
        assertThat(creditCard["last4"].asString()).matches("\\d{4}")
        assertThat(creditCard["expiry"].asString()).matches("\\d{2}/\\d{2}")

        val debitCard = cards.first { it["id"].asString() == debit.toString() }
        assertThat(debitCard["credit"].isNull).isTrue()
        assertThat(debitCard["linkedBalance"].asString()).isEqualTo("1000.00")
        assertThat(debitCard["linkedAccount"].asString()).matches("•••• \\d{4}")

        // The credit account is reached only through its card.
        val accounts = get("/api/v1/accounts", customer).json().map<JsonNode, String> { it["id"].asString() }
        assertThat(accounts).doesNotContain(fixture.cardAccount(credit).toString())
        get("/api/v1/accounts/${fixture.cardAccount(credit)}/transactions", customer).andExpect { status { isNotFound() } }
    }

    @Test
    fun `credit cards cannot be spent beyond their limit`() {
        val customer = fixture.customer()
        val credit = fixture.card(customer, credit = true, creditLimit = 100_000)
        fixture.purchase(credit, 100_000)
        assertThatThrownBy { fixture.purchase(credit, 1) }
            .isInstanceOfSatisfying(ApiException::class.java) { assertThat(it.code).isEqualTo(ErrorCode.INSUFFICIENT_FUNDS) }
    }

    @Test
    fun `freeze, unfreeze and controls within the approved daily limit`() {
        val customer = fixture.customer()
        val card = fixture.card(customer, credit = false)

        post("/api/v1/cards/$card/freeze", customer).andExpect { jsonPath("$.status") { value("frozen") } }
        post("/api/v1/cards/$card/unfreeze", customer).andExpect { jsonPath("$.status") { value("active") } }

        patch(card, customer, mapOf("overseas" to true, "dailyLimit" to "100000")).andExpect {
            status { isOk() }
            jsonPath("$.channels.overseas") { value(true) }
            jsonPath("$.channels.online") { value(true) }
            jsonPath("$.dailyLimit") { value("100000.00") }
        }
        patch(card, customer, mapOf("dailyLimit" to "200000.01")).andExpect { status { isBadRequest() } }
        patch(card, customer, mapOf("dailyLimit" to "0")).andExpect { status { isBadRequest() } }
    }

    @Test
    fun `reporting a card lost needs the PIN and moves history and points to the replacement`() {
        val customer = fixture.customer()
        val card = fixture.card(customer, credit = true, rewardPoints = 500)
        fixture.purchase(card, 12_300, merchant = "Before loss")

        post("/api/v1/cards/$card/report-lost", customer, proof(customer, "bogus-challenge")).andExpect {
            jsonPath("$.error.code") { value("CHALLENGE_INVALID") }
        }
        post("/api/v1/cards/$card/report-lost", customer, proof(customer, challenge(customer), pin = "111222")).andExpect {
            jsonPath("$.error.code") { value("PIN_INVALID") }
        }

        val replacement =
            post("/api/v1/cards/$card/report-lost", customer, proof(customer, challenge(customer)))
                .andExpect {
                    status { isOk() }
                    jsonPath("$.status") { value("active") }
                    jsonPath("$.rewardPoints") { value(500) }
                }.json()
        val newId = replacement["id"].asString()
        assertThat(newId).isNotEqualTo(card.toString())

        assertThat(get("/api/v1/cards", customer).json().map<JsonNode, String> { it["id"].asString() }).containsExactly(newId)
        get("/api/v1/cards/$card", customer).andExpect { jsonPath("$.status") { value("lost") } }
        post("/api/v1/cards/$card/freeze", customer).andExpect { status { isNotFound() } }
        val history = get("/api/v1/cards/$newId/transactions", customer).json()["items"]
        assertThat(history.map<JsonNode, String> { it["merchant"].asString() }).contains("Before loss")
    }

    @Test
    fun `full card details need Face ID, are not cached and are never stored`() {
        val customer = fixture.customer()
        val card = fixture.card(customer, credit = false)

        post("/api/v1/cards/$card/sensitive", customer, proof(customer, challenge(customer))).andExpect {
            status { isForbidden() }
            jsonPath("$.error.code") { value("STEP_UP_REQUIRED") }
        }

        val challenge = challenge(customer)
        val response =
            post("/api/v1/cards/$card/sensitive", customer, proof(customer, challenge, biometric = true))
                .andExpect {
                    status { isOk() }
                    header { string("Cache-Control", "no-store") }
                    jsonPath("$.visibleForSeconds") { value(30) }
                }.json()
        val pan = response["pan"].asString()
        assertThat(pan).hasSize(16).endsWith(get("/api/v1/cards/$card", customer).json()["last4"].asString())
        assertThat(luhnValid(pan)).isTrue()
        assertThat(response["cvv"].asString()).matches("\\d{3}")

        // Single-use challenge.
        post("/api/v1/cards/$card/sensitive", customer, proof(customer, challenge, biometric = true)).andExpect {
            jsonPath("$.error.code") { value("CHALLENGE_INVALID") }
        }
        val stored = jdbc.queryForList("SELECT CAST(c AS TEXT) AS row FROM cards c WHERE id = :id", mapOf("id" to card)).toString()
        assertThat(stored).doesNotContain(pan)
    }

    @Test
    fun `paying a credit card settles inside the ledger and lowers what is used`() {
        val customer = fixture.customer().also { fixture.deposit(it.primary, 10_000_000) }
        val card = fixture.card(customer, credit = true)
        fixture.purchase(card, 500_000)

        val inquiry =
            post("/api/v1/bills/inquiry", customer, mapOf("fromAccountId" to customer.primary, "cardId" to card, "amount" to "2000"))
                .andExpect {
                    status { isOk() }
                    jsonPath("$.amount") { value("2000.00") }
                    jsonPath("$.bill.billerCode") { value("LXCARD") }
                }.json()
        post("/api/v1/bills/inquiry", customer, mapOf("fromAccountId" to customer.primary, "cardId" to card, "amount" to "5000.01"))
            .andExpect { status { isBadRequest() } }

        val challenge = inquiry["challenge"].asString()
        mockMvc
            .post("/api/v1/bills/payments") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("Idempotency-Key", UUID.randomUUID().toString())
                contentType = MediaType.APPLICATION_JSON
                content =
                    objectMapper.writeValueAsString(
                        mapOf(
                            "inquiryId" to inquiry["inquiryId"].asString(),
                            "method" to "PIN",
                            "pin" to BankFixture.PIN,
                            "signature" to customer.deviceKey.signBase64(challenge),
                        ),
                    )
            }.andExpect { status { isOk() } }

        get("/api/v1/cards/$card", customer).andExpect { jsonPath("$.credit.used") { value("3000.00") } }
        assertThat(fixture.balance(customer.primary)).isEqualTo(10_000_000 - 200_000)
        val intruder = fixture.customer().also { fixture.deposit(it.primary, 100_000) }
        post("/api/v1/bills/inquiry", intruder, mapOf("fromAccountId" to intruder.primary, "cardId" to card)).andExpect {
            status { isNotFound() }
        }
    }

    @Test
    fun `another customer's cards are not found (BOLA)`() {
        val owner = fixture.customer()
        val intruder = fixture.customer()
        val card = fixture.card(owner, credit = true)

        get("/api/v1/cards/$card", intruder).andExpect { status { isNotFound() } }
        get("/api/v1/cards/$card/transactions", intruder).andExpect { status { isNotFound() } }
        post("/api/v1/cards/$card/freeze", intruder).andExpect { status { isNotFound() } }
        patch(card, intruder, mapOf("atm" to false)).andExpect { status { isNotFound() } }
        post("/api/v1/cards/$card/report-lost", intruder, proof(intruder, challenge(intruder))).andExpect { status { isNotFound() } }
        post("/api/v1/cards/$card/sensitive", intruder, proof(intruder, challenge(intruder), biometric = true)).andExpect {
            status { isNotFound() }
        }
        get("/api/v1/cards/${UUID.randomUUID()}", owner).andExpect { status { isNotFound() } }
    }

    private fun challenge(customer: BankFixture.Customer): String = post("/api/v1/challenges", customer).json()["challenge"].asString()

    private fun proof(
        customer: BankFixture.Customer,
        challenge: String,
        biometric: Boolean = false,
        pin: String = BankFixture.PIN,
    ): Map<String, Any?> =
        mapOf(
            "challenge" to challenge,
            "method" to if (biometric) "BIOMETRIC" else "PIN",
            "pin" to if (biometric) null else pin,
            "signature" to (if (biometric) customer.biometricKey else customer.deviceKey).signBase64(challenge),
        )

    private fun luhnValid(pan: String): Boolean =
        pan
            .reversed()
            .mapIndexed { index, char ->
                val digit = char.digitToInt()
                if (index % 2 == 1) (digit * 2).let { if (it > 9) it - 9 else it } else digit
            }.sum() % 10 == 0

    private fun get(
        path: String,
        customer: BankFixture.Customer,
    ): ResultActionsDsl = mockMvc.get(path) { header("Authorization", "Bearer ${customer.accessToken}") }

    private fun post(
        path: String,
        customer: BankFixture.Customer,
        body: Map<String, Any?>? = null,
    ): ResultActionsDsl =
        mockMvc.post(path) {
            header("Authorization", "Bearer ${customer.accessToken}")
            if (body != null) {
                contentType = MediaType.APPLICATION_JSON
                content = objectMapper.writeValueAsString(body)
            }
        }

    private fun patch(
        card: UUID,
        customer: BankFixture.Customer,
        body: Map<String, Any?>,
    ): ResultActionsDsl =
        mockMvc.patch("/api/v1/cards/$card/controls") {
            header("Authorization", "Bearer ${customer.accessToken}")
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(body)
        }

    private fun ResultActionsDsl.json(): JsonNode = objectMapper.readTree(andReturn().response.contentAsString)
}
