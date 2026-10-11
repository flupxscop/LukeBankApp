package com.luxebank.notifications

import com.luxebank.TestcontainersConfiguration
import com.luxebank.integration.PushNotifier
import com.luxebank.ledger.BankFixture
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Import
import org.springframework.context.annotation.Primary
import org.springframework.http.MediaType
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActionsDsl
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import tools.jackson.databind.JsonNode
import tools.jackson.databind.ObjectMapper
import java.time.Duration
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class, ProfileNotificationsIntegrationTest.RecordingPush::class)
class ProfileNotificationsIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
    @Autowired private val pushes: RecordingPushNotifier,
) {
    @Test
    fun `profile shows name, tier, relationship manager and preferences`() {
        val customer = fixture.customer()
        jdbc.update(
            "UPDATE users SET relationship_manager_id = '00000000-0000-0000-0000-0000000000a1' WHERE id = :id",
            mapOf("id" to customer.userId),
        )

        get("/api/v1/me", customer).andExpect {
            status { isOk() }
            jsonPath("$.firstName") { value("นกน้อย") }
            jsonPath("$.lastName") { value("ใจงาม") }
            jsonPath("$.tier") { value("GOLD") }
            jsonPath("$.relationshipManager.name") { value("นกนางน้อย ใจดี") }
            jsonPath("$.relationshipManager.phone") { value("021234567") }
            jsonPath("$.preferences.language") { value("th") }
            jsonPath("$.preferences.notifyTransactions") { value(true) }
            jsonPath("$.preferences.notifyMarketing") { value(false) }
            jsonPath("$.preferences.notifySecurity") { value(true) }
            jsonPath("$.unreadNotifications") { value(0) }
        }
        mockMvc
            .get("/api/v1/me") {
                header("Authorization", "Bearer ${customer.accessToken}")
                header("Accept-Language", "en")
            }.andExpect { jsonPath("$.relationshipManager.hours") { value("Mon–Fri 09:00–18:00") } }
    }

    @Test
    fun `preferences change partially and reject unknown languages`() {
        val customer = fixture.customer()
        patch("/api/v1/me/preferences", customer, mapOf("language" to "en", "notifyMarketing" to true)).andExpect {
            status { isOk() }
            jsonPath("$.language") { value("en") }
            jsonPath("$.notifyTransactions") { value(true) }
            jsonPath("$.notifyMarketing") { value(true) }
        }
        patch("/api/v1/me/preferences", customer, mapOf("language" to "fr")).andExpect { status { isBadRequest() } }
        get("/api/v1/me", customer).andExpect { jsonPath("$.preferences.language") { value("en") } }
    }

    @Test
    fun `devices list marks this device and the push token is stored`() {
        val customer = fixture.customer()
        get("/api/v1/me/devices", customer).andExpect {
            status { isOk() }
            jsonPath("$[0].id") { value(customer.deviceId.toString()) }
            jsonPath("$[0].current") { value(true) }
            jsonPath("$[0].biometricEnabled") { value(true) }
        }
        put("/api/v1/me/devices/current/push-token", customer, mapOf("token" to "not a token!")).andExpect { status { isBadRequest() } }
        put("/api/v1/me/devices/current/push-token", customer, mapOf("token" to token())).andExpect { status { isNoContent() } }
    }

    @Test
    fun `money in and out lands in the inbox and is pushed in the customer's language`() {
        val customer = fixture.customer()
        val token = token().also { register(customer, it) }
        fixture.deposit(customer.primary, 150_000, merchant = "Payroll")
        fixture.spend(customer.primary, 25_000, merchant = "Sarnies Bangkok")

        val page = awaitInbox(customer, 2)
        assertThat(page["unreadCount"].asInt()).isEqualTo(2)
        val titles = page["items"].map<JsonNode, String> { it["title"].asString() }
        assertThat(titles).containsExactlyInAnyOrder("เงินเข้า ฿1,500.00", "เงินออก ฿250.00")
        assertThat(page["items"].map<JsonNode, String> { it["kind"].asString() }).containsOnly("transaction")
        await { pushes.to(token).size == 2 }
        assertThat(pushes.to(token).map { it.category }).containsOnly("transaction")
    }

    @Test
    fun `turning off transaction alerts stops the push but keeps the inbox, old postings are not news`() {
        val customer = fixture.customer()
        val token = token().also { register(customer, it) }
        patch("/api/v1/me/preferences", customer, mapOf("notifyTransactions" to false)).andExpect { status { isOk() } }

        fixture.deposit(customer.primary, 10_000, at = Instant.now().minus(Duration.ofDays(3)))
        fixture.deposit(customer.primary, 20_000)

        val page = awaitInbox(customer, 1)
        assertThat(page["items"][0]["title"].asString()).isEqualTo("เงินเข้า ฿200.00")
        Thread.sleep(QUIET_MS)
        assertThat(inbox(customer)["items"].size()).isEqualTo(1)
        assertThat(pushes.to(token)).isEmpty()
    }

    @Test
    fun `security alerts are always pushed`() {
        val customer = fixture.customer()
        val token = token().also { register(customer, it) }
        patch("/api/v1/me/preferences", customer, mapOf("notifyTransactions" to false, "language" to "en")).andExpect { status { isOk() } }
        val card = fixture.card(customer, credit = false)

        post("/api/v1/cards/$card/freeze", customer).andExpect { status { isOk() } }

        await { pushes.to(token).any { it.category == "security" } }
        val alert = awaitInbox(customer, 1)["items"][0]
        assertThat(alert["kind"].asString()).isEqualTo("security")
        assertThat(alert["title"].asString()).isEqualTo("Card frozen")
        assertThat(alert["body"].asString()).matches("card x\\d{4}")
    }

    @Test
    fun `inbox can be marked read and other customers' notifications are not found`() {
        val customer = fixture.customer()
        val other = fixture.customer()
        fixture.deposit(customer.primary, 1_000)
        fixture.deposit(customer.primary, 2_000)
        val items = awaitInbox(customer, 2)["items"]
        val first = items[0]["id"].asString()

        post("/api/v1/notifications/$first/read", other).andExpect { status { isNotFound() } }
        post("/api/v1/notifications/$first/read", customer).andExpect { status { isNoContent() } }
        post("/api/v1/notifications/$first/read", customer).andExpect { status { isNoContent() } }
        assertThat(inbox(customer)["unreadCount"].asInt()).isEqualTo(1)

        post("/api/v1/notifications/read-all", customer).andExpect { status { isNoContent() } }
        assertThat(inbox(customer)["unreadCount"].asInt()).isZero()
        get("/api/v1/me", customer).andExpect { jsonPath("$.unreadNotifications") { value(0) } }
        assertThat(inbox(other)["items"].size()).isZero()
    }

    @Test
    fun `inbox pages with a cursor`() {
        val customer = fixture.customer()
        repeat(3) { fixture.deposit(customer.primary, 1_000L * (it + 1)) }
        awaitInbox(customer, 3)

        val first = get("/api/v1/notifications?limit=2", customer).json()
        assertThat(first["items"].size()).isEqualTo(2)
        val second = get("/api/v1/notifications?limit=2&cursor=${first["nextCursor"].asString()}", customer).json()
        assertThat(second["items"].size()).isEqualTo(1)
        assertThat(second["nextCursor"].isNull).isTrue()
        get("/api/v1/notifications?cursor=garbage", customer).andExpect { status { isBadRequest() } }
    }

    // --- helpers ---

    private fun register(
        customer: BankFixture.Customer,
        token: String,
    ) {
        put("/api/v1/me/devices/current/push-token", customer, mapOf("token" to token)).andExpect { status { isNoContent() } }
    }

    private fun token() = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "")

    private fun inbox(customer: BankFixture.Customer): JsonNode = get("/api/v1/notifications", customer).json()

    private fun awaitInbox(
        customer: BankFixture.Customer,
        count: Int,
    ): JsonNode {
        await { inbox(customer)["items"].size() >= count }
        return inbox(customer)
    }

    private fun await(condition: () -> Boolean) {
        val deadline = System.nanoTime() + Duration.ofSeconds(TIMEOUT_SECONDS).toNanos()
        while (!condition()) {
            check(System.nanoTime() < deadline) { "Condition not met in time" }
            Thread.sleep(POLL_MS)
        }
    }

    private fun get(
        path: String,
        customer: BankFixture.Customer,
    ): ResultActionsDsl = mockMvc.get(path) { header("Authorization", "Bearer ${customer.accessToken}") }

    private fun post(
        path: String,
        customer: BankFixture.Customer,
    ): ResultActionsDsl = mockMvc.post(path) { header("Authorization", "Bearer ${customer.accessToken}") }

    private fun patch(
        path: String,
        customer: BankFixture.Customer,
        body: Map<String, Any?>,
    ): ResultActionsDsl =
        mockMvc.patch(path) {
            header("Authorization", "Bearer ${customer.accessToken}")
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(body)
        }

    private fun put(
        path: String,
        customer: BankFixture.Customer,
        body: Map<String, Any?>,
    ): ResultActionsDsl =
        mockMvc.put(path) {
            header("Authorization", "Bearer ${customer.accessToken}")
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(body)
        }

    private fun ResultActionsDsl.json(): JsonNode = objectMapper.readTree(andReturn().response.contentAsString)

    data class Push(
        val token: String,
        val title: String,
        val category: String,
    )

    class RecordingPushNotifier : PushNotifier {
        private val sent = CopyOnWriteArrayList<Push>()

        override fun send(
            pushToken: String,
            title: String,
            body: String,
            category: String,
        ) {
            sent += Push(pushToken, title, category)
        }

        fun to(token: String) = sent.filter { it.token == token }
    }

    @TestConfiguration
    class RecordingPush {
        @Bean
        @Primary
        fun recordingPushNotifier() = RecordingPushNotifier()
    }

    private companion object {
        const val TIMEOUT_SECONDS = 5L
        const val POLL_MS = 50L
        const val QUIET_MS = 300L
    }
}
