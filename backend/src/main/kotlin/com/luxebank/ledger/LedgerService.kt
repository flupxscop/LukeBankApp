package com.luxebank.ledger

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.security.SecureRandom
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID

/** What the customer sees for their side of an entry (spec section 8 "Transaction"). */
data class EntryDetails(
    val merchant: String,
    val category: Category,
    val channel: Channel,
    val monogram: String? = null,
    val memo: String? = null,
)

/** One side of a journal entry. Customer-account lines need [details]; internal accounts do not. */
data class Line(
    val accountId: UUID,
    val amountSatang: Long,
    val details: EntryDetails? = null,
)

/**
 * The only writer of money (spec 7.2, 13.2 Integrity). Every entry is double-entry and sums to zero;
 * the database re-checks that at commit, keeps postings append-only and rejects negative customer balances.
 */
@Service
class LedgerService(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val random = SecureRandom()

    @Transactional
    fun post(
        type: JournalType,
        lines: List<Line>,
        occurredAt: Instant = Instant.now(),
        idempotencyKey: String? = null,
    ): UUID {
        require(lines.size >= 2) { "A journal entry needs at least two postings" }
        require(lines.none { it.amountSatang == 0L }) { "Postings cannot be zero" }
        require(lines.sumOf { it.amountSatang } == 0L) { "Postings must sum to zero" }

        if (idempotencyKey != null) {
            existingEntry(idempotencyKey)?.let { return it }
        }

        val accounts = lockAccounts(lines.map { it.accountId }.distinct())
        lines.groupBy { it.accountId }.forEach { (accountId, accountLines) ->
            val account = accounts.getValue(accountId)
            if (!account.internal) {
                require(accountLines.all { it.details != null }) { "Customer postings need details" }
                if (account.status != "active") throw ApiException(ErrorCode.ACCOUNT_UNAVAILABLE, "Account is not active")
                if (account.balance + accountLines.sumOf { it.amountSatang } < 0) {
                    throw ApiException(ErrorCode.INSUFFICIENT_FUNDS, "Insufficient funds")
                }
            }
        }

        val entryId = UUID.randomUUID()
        jdbc.update(
            """
            INSERT INTO journal_entries (id, type, reference_no, idempotency_key, status, occurred_at)
            VALUES (:id, :type, :ref, :key, 'posted', :at)
            """,
            mapOf("id" to entryId, "type" to type.code, "ref" to referenceNo(occurredAt), "key" to idempotencyKey, "at" to ts(occurredAt)),
        )
        for (line in lines) {
            val params = mapOf("entry" to entryId, "account" to line.accountId, "amount" to line.amountSatang)
            jdbc.update("INSERT INTO postings (journal_entry_id, account_id, amount_satang) VALUES (:entry, :account, :amount)", params)
            // Only customer accounts keep a balance snapshot; internal accounts are summed from postings,
            // so the clearing account is never a row every external payment must queue on.
            if (!accounts.getValue(line.accountId).internal) {
                jdbc.update(
                    "UPDATE accounts SET balance_satang = balance_satang + :amount, version = version + 1 WHERE id = :account",
                    params,
                )
            }
            line.details?.let { insertTransaction(entryId, line, it, occurredAt) }
        }
        return entryId
    }

    /** Customer accounts whose balance snapshot differs from the sum of their postings. Empty means reconciled. */
    @Transactional(readOnly = true)
    fun unreconciledAccounts(): List<UUID> =
        jdbc.query(
            """
            SELECT a.id FROM accounts a
            LEFT JOIN (SELECT account_id, SUM(amount_satang) AS total FROM postings GROUP BY account_id) p ON p.account_id = a.id
            WHERE a.user_id IS NOT NULL AND a.balance_satang <> COALESCE(p.total, 0)
            """,
            emptyMap<String, Any>(),
        ) { rs, _ -> rs.getObject(1, UUID::class.java) }

    private fun existingEntry(key: String): UUID? =
        jdbc
            .query("SELECT id FROM journal_entries WHERE idempotency_key = :key", mapOf("key" to key)) { rs, _ ->
                rs.getObject(1, UUID::class.java)
            }.firstOrNull()

    private data class LockedAccount(
        val internal: Boolean,
        val status: String,
        val balance: Long,
    )

    /**
     * Locks customer accounts in id order so concurrent entries cannot deadlock. Internal accounts are read
     * without a lock: they have no balance rule to protect and would otherwise serialise every payment.
     */
    private fun lockAccounts(ids: List<UUID>): Map<UUID, LockedAccount> {
        val mapper = { rs: java.sql.ResultSet, _: Int ->
            rs.getObject("id", UUID::class.java) to
                LockedAccount(rs.getBoolean("internal"), rs.getString("status"), rs.getLong("balance_satang"))
        }
        val columns = "SELECT id, user_id IS NULL AS internal, status, balance_satang FROM accounts WHERE id IN (:ids)"
        val rows =
            jdbc.query("$columns AND user_id IS NOT NULL ORDER BY id FOR UPDATE", mapOf("ids" to ids), mapper) +
                jdbc.query("$columns AND user_id IS NULL", mapOf("ids" to ids), mapper)
        if (rows.size != ids.size) throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        return rows.toMap()
    }

    private fun insertTransaction(
        entryId: UUID,
        line: Line,
        details: EntryDetails,
        occurredAt: Instant,
    ) {
        jdbc.update(
            """
            INSERT INTO transactions (id, account_id, journal_entry_id, merchant, monogram, category, channel, amount_satang, memo, occurred_at)
            VALUES (:id, :account, :entry, :merchant, :monogram, :category, :channel, :amount, :memo, :at)
            """,
            mapOf(
                "id" to UUID.randomUUID(),
                "account" to line.accountId,
                "entry" to entryId,
                "merchant" to details.merchant,
                "monogram" to details.monogram,
                "category" to details.category.code,
                "channel" to details.channel.code,
                "amount" to line.amountSatang,
                "memo" to details.memo,
                "at" to ts(occurredAt),
            ),
        )
    }

    /** e.g. LX261010K7M2Q9XA4C — date plus 10 random characters, unique by constraint. */
    private fun referenceNo(occurredAt: Instant): String {
        val date = LocalDate.ofInstant(occurredAt, BankTime.ZONE).format(DateTimeFormatter.ofPattern("yyMMdd"))
        val suffix = (1..REF_RANDOM_CHARS).map { REF_ALPHABET[random.nextInt(REF_ALPHABET.length)] }.joinToString("")
        return "LX$date$suffix"
    }

    private fun ts(instant: Instant) = Timestamp.from(instant)

    private companion object {
        const val REF_RANDOM_CHARS = 10
        const val REF_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    }
}
