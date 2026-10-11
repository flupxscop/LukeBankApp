package com.luxebank.transactions

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import com.luxebank.ledger.Direction
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import java.nio.ByteBuffer
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.util.Base64
import java.util.UUID

data class TransactionRow(
    val id: UUID,
    val accountId: UUID,
    val merchant: String,
    val monogram: String?,
    val category: String,
    val channel: String,
    val amountSatang: Long,
    val memo: String?,
    val occurredAt: Instant,
)

data class TransactionDetailRow(
    val transaction: TransactionRow,
    val referenceNo: String,
    val status: String,
    val accountName: String,
    val accountNumber: String,
    val hasSlip: Boolean,
)

data class TransactionFilter(
    val from: LocalDate? = null,
    val to: LocalDate? = null,
    val category: Category? = null,
    val direction: Direction? = null,
    val query: String? = null,
)

data class TransactionPage(
    val items: List<TransactionRow>,
    val nextCursor: String?,
)

data class Totals(
    val inSatang: Long,
    val outSatang: Long,
)

/** Keyset cursor over (occurred_at DESC, id DESC); opaque to clients (TXN-01). */
data class Cursor(
    val occurredAt: Instant,
    val id: UUID,
) {
    fun encode(): String {
        val buffer = ByteBuffer.allocate(CURSOR_BYTES)
        buffer.putLong(occurredAt.epochSecond).putInt(occurredAt.nano)
        buffer.putLong(id.mostSignificantBits).putLong(id.leastSignificantBits)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buffer.array())
    }

    companion object {
        private const val CURSOR_BYTES = 28

        fun decode(value: String): Cursor {
            val bytes = runCatching { Base64.getUrlDecoder().decode(value) }.getOrNull()
            if (bytes == null || bytes.size != CURSOR_BYTES) throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")
            val buffer = ByteBuffer.wrap(bytes)
            val instant = runCatching { Instant.ofEpochSecond(buffer.long, buffer.int.toLong()) }.getOrNull()
            return Cursor(instant ?: throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid"), UUID(buffer.long, buffer.long))
        }
    }
}

@Repository
class TransactionQueries(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val mapper =
        RowMapper { rs, _ ->
            TransactionRow(
                id = rs.getObject("id", UUID::class.java),
                accountId = rs.getObject("account_id", UUID::class.java),
                merchant = rs.getString("merchant"),
                monogram = rs.getString("monogram"),
                category = rs.getString("category"),
                channel = rs.getString("channel"),
                amountSatang = rs.getLong("amount_satang"),
                memo = rs.getString("memo"),
                occurredAt = rs.getTimestamp("occurred_at").toInstant(),
            )
        }

    fun page(
        accountId: UUID,
        filter: TransactionFilter,
        cursor: Cursor?,
        limit: Int,
    ): TransactionPage {
        val (where, params) = conditions(accountId, filter)
        if (cursor != null) {
            where += "(t.occurred_at, t.id) < (:cursorAt, :cursorId)"
            params["cursorAt"] = Timestamp.from(cursor.occurredAt)
            params["cursorId"] = cursor.id
        }
        params["limit"] = limit + 1
        val rows =
            jdbc.query(
                "SELECT t.* FROM transactions t WHERE ${where.joinToString(" AND ")} ORDER BY t.occurred_at DESC, t.id DESC LIMIT :limit",
                params,
                mapper,
            )
        val items = rows.take(limit)
        val next = if (rows.size > limit) items.last().let { Cursor(it.occurredAt, it.id).encode() } else null
        return TransactionPage(items, next)
    }

    /** Purchases made with any of [cardIds], newest first (CARD-09). */
    fun cardPage(
        cardIds: List<UUID>,
        cursor: Cursor?,
        limit: Int,
    ): TransactionPage {
        val params = mutableMapOf<String, Any?>("cards" to cardIds, "limit" to limit + 1)
        val where = mutableListOf("t.card_id IN (:cards)")
        if (cursor != null) {
            where += "(t.occurred_at, t.id) < (:cursorAt, :cursorId)"
            params["cursorAt"] = Timestamp.from(cursor.occurredAt)
            params["cursorId"] = cursor.id
        }
        val rows =
            jdbc.query(
                "SELECT t.* FROM transactions t WHERE ${where.joinToString(" AND ")} ORDER BY t.occurred_at DESC, t.id DESC LIMIT :limit",
                params,
                mapper,
            )
        val items = rows.take(limit)
        return TransactionPage(items, if (rows.size > limit) items.last().let { Cursor(it.occurredAt, it.id).encode() } else null)
    }

    fun totals(
        accountId: UUID,
        filter: TransactionFilter,
    ): Totals {
        val (where, params) = conditions(accountId, filter)
        return jdbc.queryForObject(
            """
            SELECT COALESCE(SUM(amount_satang) FILTER (WHERE amount_satang > 0), 0) AS money_in,
                   COALESCE(-SUM(amount_satang) FILTER (WHERE amount_satang < 0), 0) AS money_out
            FROM transactions t WHERE ${where.joinToString(" AND ")}
            """,
            params,
        ) { rs, _ -> Totals(rs.getLong("money_in"), rs.getLong("money_out")) }
    }

    fun findOwned(
        userId: UUID,
        transactionId: UUID,
    ): TransactionDetailRow? =
        jdbc
            .query(
                """
                SELECT t.*, j.reference_no, j.status, a.name AS account_name, a.account_number,
                       EXISTS (SELECT 1 FROM payments p WHERE p.transaction_id = t.id) AS has_slip
                FROM transactions t
                JOIN accounts a ON a.id = t.account_id
                JOIN journal_entries j ON j.id = t.journal_entry_id
                WHERE t.id = :id AND a.user_id = :user
                """,
                mapOf("id" to transactionId, "user" to userId),
            ) { rs, n ->
                TransactionDetailRow(
                    transaction = checkNotNull(mapper.mapRow(rs, n)),
                    referenceNo = rs.getString("reference_no"),
                    status = rs.getString("status"),
                    accountName = rs.getString("account_name"),
                    accountNumber = rs.getString("account_number"),
                    hasSlip = rs.getBoolean("has_slip"),
                )
            }.firstOrNull()

    /** Changes the category and/or memo (TXN-05). [memo] is only written when [setMemo] is true; null clears it. */
    fun update(
        transactionId: UUID,
        category: Category?,
        setMemo: Boolean,
        memo: String?,
    ) {
        jdbc.update(
            """
            UPDATE transactions
            SET category = COALESCE(:category, category),
                memo = CASE WHEN :setMemo THEN CAST(:memo AS VARCHAR) ELSE memo END,
                version = version + 1
            WHERE id = :id
            """,
            mapOf("id" to transactionId, "category" to category?.code, "setMemo" to setMemo, "memo" to memo),
        )
    }

    private fun conditions(
        accountId: UUID,
        filter: TransactionFilter,
    ): Pair<MutableList<String>, MutableMap<String, Any?>> {
        val where = mutableListOf("t.account_id = :account")
        val params = mutableMapOf<String, Any?>("account" to accountId)
        filter.from?.let {
            where += "t.occurred_at >= :from"
            params["from"] = Timestamp.from(it.atStartOfDay(BankTime.ZONE).toInstant())
        }
        filter.to?.let {
            where += "t.occurred_at < :to"
            params["to"] = Timestamp.from(it.plusDays(1).atStartOfDay(BankTime.ZONE).toInstant())
        }
        filter.category?.let {
            where += "t.category = :category"
            params["category"] = it.code
        }
        when (filter.direction) {
            Direction.IN -> where += "t.amount_satang > 0"
            Direction.OUT -> where += "t.amount_satang < 0"
            null -> Unit
        }
        filter.query?.takeIf { it.isNotBlank() }?.let {
            where += "(t.merchant ILIKE :q ESCAPE '\\' OR t.memo ILIKE :q ESCAPE '\\')"
            params["q"] = "%" + escapeLike(it.trim()) + "%"
        }
        return where to params
    }

    /** User text is matched literally: %, _ and \ lose their LIKE meaning. */
    private fun escapeLike(value: String) =
        value
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")
}
