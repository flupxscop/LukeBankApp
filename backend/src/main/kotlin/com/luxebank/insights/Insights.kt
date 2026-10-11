package com.luxebank.insights

import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import com.luxebank.ledger.Money
import com.luxebank.ledger.SpendingKind
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.sql.Date
import java.sql.Timestamp
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeParseException
import java.util.UUID

data class KindSpending(
    val kind: String,
    val spent: String,
    val budget: String,
)

data class CategorySpending(
    val category: String,
    val spent: String,
)

data class SpendingInsight(
    val month: String,
    val totalSpent: String,
    val totalBudget: String,
    val categories: List<KindSpending>,
    val byCategory: List<CategorySpending>,
)

/** Monthly spending against budget, computed on the server (DASH-06). Transfers, investments and income are not spending. */
@Service
class InsightsService(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    @Transactional(readOnly = true)
    fun spending(
        userId: UUID,
        month: YearMonth,
    ): SpendingInsight {
        val byCategory = spentByCategory(userId, month)
        val budgets = budgets(userId, month)
        val kinds =
            SpendingKind.entries.map { kind ->
                val spent = byCategory.filterKeys { it.kind == kind }.values.sum()
                Triple(kind, spent, budgets[kind] ?: 0L)
            }
        return SpendingInsight(
            month = month.toString(),
            totalSpent = Money.format(kinds.sumOf { it.second }),
            totalBudget = Money.format(kinds.sumOf { it.third }),
            categories = kinds.map { (kind, spent, budget) -> KindSpending(kind.code, Money.format(spent), Money.format(budget)) },
            byCategory =
                byCategory.entries
                    .sortedByDescending { it.value }
                    .map { CategorySpending(it.key.code, Money.format(it.value)) },
        )
    }

    /** Sum of credits in [category] across the customer's accounts, e.g. cashback. */
    @Transactional(readOnly = true)
    fun earned(
        userId: UUID,
        category: Category,
        from: Instant,
        to: Instant,
    ): Long =
        jdbc.queryForObject(
            """
            SELECT COALESCE(SUM(t.amount_satang), 0) FROM transactions t JOIN accounts a ON a.id = t.account_id
            WHERE a.user_id = :user AND t.category = :category AND t.amount_satang > 0 AND t.occurred_at >= :from AND t.occurred_at < :to
            """,
            mapOf("user" to userId, "category" to category.code, "from" to Timestamp.from(from), "to" to Timestamp.from(to)),
            Long::class.java,
        ) ?: 0L

    private fun spentByCategory(
        userId: UUID,
        month: YearMonth,
    ): Map<Category, Long> {
        val rows =
            jdbc.query(
                """
                SELECT t.category, -SUM(t.amount_satang) AS spent FROM transactions t JOIN accounts a ON a.id = t.account_id
                WHERE a.user_id = :user AND t.amount_satang < 0 AND t.category IN (:categories)
                  AND t.occurred_at >= :from AND t.occurred_at < :to
                GROUP BY t.category
                """,
                mapOf(
                    "user" to userId,
                    "categories" to Category.spending().map { it.code },
                    "from" to Timestamp.from(startOf(month)),
                    "to" to Timestamp.from(startOf(month.plusMonths(1))),
                ),
            ) { rs, _ -> Category.parse(rs.getString("category")) to rs.getLong("spent") }
        return rows.mapNotNull { (category, spent) -> category?.let { it to spent } }.toMap()
    }

    /** The budget set for the month, or the latest earlier one if the customer has not changed it. */
    private fun budgets(
        userId: UUID,
        month: YearMonth,
    ): Map<SpendingKind, Long> =
        jdbc
            .query(
                """
                SELECT DISTINCT ON (kind) kind, limit_satang FROM spending_budgets
                WHERE user_id = :user AND month <= :month ORDER BY kind, month DESC
                """,
                mapOf("user" to userId, "month" to Date.valueOf(month.atDay(1))),
            ) { rs, _ -> SpendingKind.valueOf(rs.getString("kind").uppercase()) to rs.getLong("limit_satang") }
            .toMap()

    companion object {
        fun startOf(month: YearMonth): Instant = month.atDay(1).atStartOfDay(BankTime.ZONE).toInstant()

        fun startOf(day: LocalDate): Instant = day.atStartOfDay(BankTime.ZONE).toInstant()
    }
}

@RestController
@RequestMapping("/api/v1/insights")
class InsightsController(
    private val insights: InsightsService,
    private val clock: Clock,
) {
    @GetMapping("/spending")
    fun spending(
        current: CurrentDevice,
        @RequestParam(required = false) month: String?,
    ): SpendingInsight {
        val parsed =
            month?.let {
                try {
                    YearMonth.parse(it)
                } catch (_: DateTimeParseException) {
                    throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")
                }
            } ?: YearMonth.now(clock)
        return insights.spending(current.userId, parsed)
    }
}
