package com.luxebank.dashboard

import com.luxebank.accounts.AccountQueries
import com.luxebank.accounts.AccountResponse
import com.luxebank.accounts.AccountRow
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.insights.InsightsService
import com.luxebank.insights.KindSpending
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import com.luxebank.ledger.Money
import com.luxebank.transactions.TransactionFilter
import com.luxebank.transactions.TransactionQueries
import com.luxebank.transactions.TransactionResponse
import com.luxebank.users.UserRepository
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.math.RoundingMode
import java.sql.Timestamp
import java.time.Clock
import java.time.LocalDate
import java.time.YearMonth
import java.util.UUID

@Configuration
class ClockConfig {
    @Bean
    fun clock(): Clock = BankTime.clock()
}

data class BalancePoint(
    val date: LocalDate,
    val balance: String,
)

data class SpendingSummary(
    val categories: List<KindSpending>,
)

data class SavingsGoalResponse(
    val name: String,
    val saved: String,
    val target: String,
)

data class DashboardResponse(
    val customerFirstName: String,
    val primaryAccount: AccountResponse,
    val accounts: List<AccountResponse>,
    val monthChange: String,
    val monthChangeRate: String,
    val balanceHistory: List<BalancePoint>,
    val cashbackThisMonth: String,
    val cashbackTrend: List<String>,
    val spending: SpendingSummary,
    val savingsGoal: SavingsGoalResponse?,
    val recentTransactions: List<TransactionResponse>,
)

/** Everything the home screen needs in one call (spec section 9 `/dashboard`, DASH-01…10). */
@Service
class DashboardService(
    private val users: UserRepository,
    private val accounts: AccountQueries,
    private val transactions: TransactionQueries,
    private val insights: InsightsService,
    private val jdbc: NamedParameterJdbcTemplate,
    private val clock: Clock,
) {
    @Transactional(readOnly = true)
    fun dashboard(
        userId: UUID,
        english: Boolean,
    ): DashboardResponse {
        val user = users.findById(userId).orElseThrow { ApiException(ErrorCode.NOT_FOUND, "Resource not found") }
        val owned = accounts.listForUser(userId)
        val primary = owned.firstOrNull() ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        val today = LocalDate.now(clock)
        val history = balanceHistory(primary, today)
        val monthAgo = history[history.size - 1 - MONTH_DAYS].second
        val change = primary.balanceSatang - monthAgo

        return DashboardResponse(
            customerFirstName = if (english) user.firstNameEn else user.firstNameTh,
            primaryAccount = AccountResponse.of(primary),
            accounts = owned.map(AccountResponse::of),
            monthChange = Money.format(change),
            monthChangeRate = changeRate(change, monthAgo),
            balanceHistory = history.map { (day, balance) -> BalancePoint(day, Money.format(balance)) },
            cashbackThisMonth =
                Money.format(
                    insights.earned(
                        userId,
                        Category.CASHBACK,
                        InsightsService.startOf(YearMonth.from(today)),
                        InsightsService.startOf(today.plusDays(1)),
                    ),
                ),
            cashbackTrend = cashbackTrend(userId, today),
            spending = SpendingSummary(insights.spending(userId, YearMonth.from(today)).categories),
            savingsGoal = savingsGoal(userId),
            recentTransactions =
                transactions.page(primary.id, TransactionFilter(), null, RECENT).items.map(TransactionResponse::of),
        )
    }

    /** Closing balance for each of the last [HISTORY_DAYS] days, oldest first, walked back from today's balance. */
    private fun balanceHistory(
        account: AccountRow,
        today: LocalDate,
    ): List<Pair<LocalDate, Long>> {
        val start = today.minusDays(HISTORY_DAYS - 1L)
        val dailyNet =
            jdbc
                .query(
                    """
                    SELECT (j.occurred_at AT TIME ZONE 'Asia/Bangkok')::date AS day, SUM(p.amount_satang) AS net
                    FROM postings p JOIN journal_entries j ON j.id = p.journal_entry_id
                    WHERE p.account_id = :account AND j.occurred_at >= :from
                    GROUP BY day
                    """,
                    mapOf("account" to account.id, "from" to Timestamp.from(InsightsService.startOf(start.plusDays(1)))),
                ) { rs, _ -> rs.getObject("day", LocalDate::class.java) to rs.getLong("net") }
                .toMap()

        var balance = account.balanceSatang
        val points = ArrayList<Pair<LocalDate, Long>>(HISTORY_DAYS)
        var day = today
        while (!day.isBefore(start)) {
            points += day to balance
            balance -= dailyNet[day] ?: 0L
            day = day.minusDays(1)
        }
        return points.reversed()
    }

    /** Weekly cashback for the last [TREND_WEEKS] weeks ending today, oldest first. */
    private fun cashbackTrend(
        userId: UUID,
        today: LocalDate,
    ): List<String> =
        (TREND_WEEKS - 1 downTo 0).map { weeksAgo ->
            val end = today.plusDays(1).minusWeeks(weeksAgo.toLong())
            Money.format(
                insights.earned(userId, Category.CASHBACK, InsightsService.startOf(end.minusWeeks(1)), InsightsService.startOf(end)),
            )
        }

    private fun savingsGoal(userId: UUID): SavingsGoalResponse? =
        jdbc
            .query(
                """
                SELECT g.name, g.target_satang, a.balance_satang FROM savings_goals g JOIN accounts a ON a.id = g.account_id
                WHERE g.user_id = :user AND a.user_id = :user
                """,
                mapOf("user" to userId),
            ) { rs, _ ->
                SavingsGoalResponse(
                    rs.getString("name"),
                    Money.format(rs.getLong("balance_satang")),
                    Money.format(rs.getLong("target_satang")),
                )
            }.firstOrNull()

    private fun changeRate(
        change: Long,
        base: Long,
    ): String {
        if (base <= 0) return "0.0"
        return BigDecimal(change)
            .multiply(BigDecimal(PERCENT))
            .divide(BigDecimal(base), 1, RoundingMode.HALF_UP)
            .toPlainString()
    }

    private companion object {
        const val HISTORY_DAYS = 365
        const val MONTH_DAYS = 30
        const val TREND_WEEKS = 5
        const val RECENT = 5
        const val PERCENT = 100
    }
}

@RestController
@RequestMapping("/api/v1/dashboard")
class DashboardController(
    private val dashboard: DashboardService,
) {
    @GetMapping
    fun get(
        current: CurrentDevice,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): DashboardResponse = dashboard.dashboard(current.userId, language?.startsWith("en") == true)
}
