package com.luxebank.dashboard

import com.luxebank.TestcontainersConfiguration
import com.luxebank.ledger.BankFixture
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import com.luxebank.ledger.SpendingKind
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import tools.jackson.databind.JsonNode
import tools.jackson.databind.ObjectMapper
import java.time.LocalDate
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class DashboardIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
) {
    private val today = LocalDate.now(BankTime.ZONE)

    @Test
    fun `dashboard is computed from the ledger`() {
        val customer = fixture.customer()
        val monthStart = today.withDayOfMonth(1)
        fixture.deposit(customer.primary, 1_000_000_00, fixture.at(today.minusDays(60)))
        fixture.deposit(customer.primary, 50_000_00, fixture.at(today.minusDays(10)))
        fixture.deposit(
            customer.primary,
            1_200_00,
            fixture.at(today, hour = 1),
            merchant = "LuxeBank Cashback",
            category = Category.CASHBACK,
        )
        fixture.spend(customer.primary, 380_00, fixture.at(today, hour = 2), category = Category.FOOD)
        fixture.spend(customer.primary, 124_00, fixture.at(today, hour = 3), category = Category.TRANSPORT)
        fixture.spend(customer.primary, 99_00, fixture.at(today, hour = 4), merchant = "Transfer out", category = Category.TRANSFER)
        fixture.budget(customer.userId, SpendingKind.LIFESTYLE, monthStart.minusMonths(2), 50_000_00)
        fixture.budget(customer.userId, SpendingKind.TRAVEL, monthStart, 25_000_00)
        jdbc.update(
            "INSERT INTO savings_goals (id, user_id, account_id, name, target_satang) VALUES (:id, :user, :account, 'Japan', 24000000)",
            mapOf("id" to UUID.randomUUID(), "user" to customer.userId, "account" to customer.savings),
        )

        val body = dashboard(customer.accessToken, "en")

        val balance = 1_000_000_00L + 50_000_00 + 1_200_00 - 380_00 - 124_00 - 99_00
        assertThat(body["customerFirstName"].asString()).isEqualTo("Noknoi")
        assertThat(dashboard(customer.accessToken, "th")["customerFirstName"].asString()).isEqualTo("นกน้อย")
        assertThat(body["primaryAccount"]["id"].asString()).isEqualTo(customer.primary.toString())
        assertThat(body["primaryAccount"]["balance"].asString()).isEqualTo(money(balance))
        assertThat(body["accounts"]).hasSize(2)

        val history = body["balanceHistory"]
        assertThat(history).hasSize(365)
        assertThat(history.last()["date"].asString()).isEqualTo(today.toString())
        assertThat(history.last()["balance"].asString()).isEqualTo(money(balance))
        assertThat(history[364 - 30]["balance"].asString()).isEqualTo("1000000.00")
        assertThat(history.first()["balance"].asString()).isEqualTo("0.00")
        assertThat(body["monthChange"].asString()).isEqualTo(money(balance - 1_000_000_00))
        assertThat(body["monthChangeRate"].asString()).isEqualTo("5.1")

        assertThat(body["cashbackThisMonth"].asString()).isEqualTo("1200.00")
        assertThat(body["cashbackTrend"].map<JsonNode, String> { it.asString() }).containsExactly("0.00", "0.00", "0.00", "0.00", "1200.00")

        val spending =
            body["spending"]["categories"].associate {
                it["kind"].asString() to
                    (it["spent"].asString() to it["budget"].asString())
            }
        assertThat(spending["lifestyle"]).isEqualTo("380.00" to "50000.00")
        assertThat(spending["travel"]).isEqualTo("124.00" to "25000.00")

        assertThat(body["savingsGoal"]["target"].asString()).isEqualTo("240000.00")
        assertThat(body["savingsGoal"]["saved"].asString()).isEqualTo("0.00")
        assertThat(body["recentTransactions"]).hasSize(5)
        assertThat(body["recentTransactions"][0]["merchant"].asString()).isEqualTo("Transfer out")
    }

    @Test
    fun `customer without accounts gets not found and a month change of zero is not a division error`() {
        val empty = fixture.customer(withAccounts = false)
        mockMvc.get("/api/v1/dashboard") { header("Authorization", "Bearer ${empty.accessToken}") }.andExpect {
            status { isNotFound() }
        }

        val fresh = fixture.customer()
        val body = dashboard(fresh.accessToken, "th")
        assertThat(body["monthChangeRate"].asString()).isEqualTo("0.0")
        assertThat(body["savingsGoal"].isNull).isTrue()
        assertThat(body["spending"]["categories"].map<JsonNode, String> { it["budget"].asString() }).containsOnly("0.00")
    }

    @Test
    fun `spending insight validates the month`() {
        val customer = fixture.customer()
        mockMvc
            .get("/api/v1/insights/spending") {
                header("Authorization", "Bearer ${customer.accessToken}")
                param("month", "2026-13")
            }.andExpect { status { isBadRequest() } }
        mockMvc
            .get("/api/v1/insights/spending") { header("Authorization", "Bearer ${customer.accessToken}") }
            .andExpect {
                status { isOk() }
                jsonPath("$.month") { value(today.toString().take(7)) }
            }
    }

    private fun dashboard(
        token: String,
        language: String,
    ): JsonNode =
        objectMapper.readTree(
            mockMvc
                .get("/api/v1/dashboard") {
                    header("Authorization", "Bearer $token")
                    header("Accept-Language", language)
                }.andExpect { status { isOk() } }
                .andReturn()
                .response.contentAsString,
        )

    private fun money(satang: Long) = "%d.%02d".format(satang / 100, satang % 100)
}
