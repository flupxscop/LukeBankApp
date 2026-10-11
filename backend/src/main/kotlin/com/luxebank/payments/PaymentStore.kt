package com.luxebank.payments

import com.luxebank.ledger.BankTime
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

enum class PaymentKind { TRANSFER, BILL }

enum class RecipientType {
    OWN,
    INTERNAL,
    OTHER_BANK,
    PROMPTPAY,
    BILL,
    ;

    val code: String get() = name.lowercase()

    companion object {
        fun parse(code: String): RecipientType? = entries.firstOrNull { it.code == code }
    }
}

/** A priced, name-checked payment that only needs the customer's confirmation. */
data class Inquiry(
    val id: UUID,
    val userId: UUID,
    val deviceId: UUID,
    val kind: PaymentKind,
    val recipientType: RecipientType,
    val fromAccountId: UUID,
    val toAccountId: UUID?,
    val bankCode: String?,
    val accountOrProxy: String?,
    /** Full name for external recipients and billers; masked before it leaves the server. */
    val recipientName: String,
    val billerCode: String?,
    val ref1: String?,
    val ref2: String?,
    val amountSatang: Long,
    val feeSatang: Long,
    val memo: String?,
    val challenge: String,
    val requiresBiometric: Boolean,
    val expiresAt: Instant,
    val consumedAt: Instant?,
)

data class StoredPayment(
    val inquiryId: UUID,
    val transactionId: UUID,
)

@Repository
class PaymentStore(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val inquiryMapper =
        RowMapper { rs, _ ->
            Inquiry(
                id = rs.getObject("id", UUID::class.java),
                userId = rs.getObject("user_id", UUID::class.java),
                deviceId = rs.getObject("device_id", UUID::class.java),
                kind = PaymentKind.valueOf(rs.getString("kind").uppercase()),
                recipientType = RecipientType.valueOf(rs.getString("recipient_type").uppercase()),
                fromAccountId = rs.getObject("from_account_id", UUID::class.java),
                toAccountId = rs.getObject("to_account_id", UUID::class.java),
                bankCode = rs.getString("bank_code"),
                accountOrProxy = rs.getString("account_or_proxy"),
                recipientName = rs.getString("recipient_name"),
                billerCode = rs.getString("biller_code"),
                ref1 = rs.getString("ref1"),
                ref2 = rs.getString("ref2"),
                amountSatang = rs.getLong("amount_satang"),
                feeSatang = rs.getLong("fee_satang"),
                memo = rs.getString("memo"),
                challenge = rs.getString("challenge"),
                requiresBiometric = rs.getBoolean("requires_biometric"),
                expiresAt = rs.getTimestamp("expires_at").toInstant(),
                consumedAt = rs.getTimestamp("consumed_at")?.toInstant(),
            )
        }

    fun insert(inquiry: Inquiry) {
        jdbc.update(
            """
            INSERT INTO payment_inquiries (id, user_id, device_id, kind, recipient_type, from_account_id, to_account_id, bank_code,
                account_or_proxy, recipient_name, biller_code, ref1, ref2, amount_satang, fee_satang, memo, challenge,
                requires_biometric, expires_at)
            VALUES (:id, :user, :device, :kind, :type, :from, :to, :bank, :account, :name, :biller, :ref1, :ref2, :amount, :fee,
                :memo, :challenge, :biometric, :expires)
            """,
            mapOf(
                "id" to inquiry.id,
                "user" to inquiry.userId,
                "device" to inquiry.deviceId,
                "kind" to inquiry.kind.name.lowercase(),
                "type" to inquiry.recipientType.code,
                "from" to inquiry.fromAccountId,
                "to" to inquiry.toAccountId,
                "bank" to inquiry.bankCode,
                "account" to inquiry.accountOrProxy,
                "name" to inquiry.recipientName,
                "biller" to inquiry.billerCode,
                "ref1" to inquiry.ref1,
                "ref2" to inquiry.ref2,
                "amount" to inquiry.amountSatang,
                "fee" to inquiry.feeSatang,
                "memo" to inquiry.memo,
                "challenge" to inquiry.challenge,
                "biometric" to inquiry.requiresBiometric,
                "expires" to Timestamp.from(inquiry.expiresAt),
            ),
        )
    }

    /** Scoped to the customer and the device that asked for it; anyone else's reads as missing. */
    fun findOwned(
        id: UUID,
        userId: UUID,
        deviceId: UUID,
    ): Inquiry? =
        jdbc
            .query(
                "SELECT * FROM payment_inquiries WHERE id = :id AND user_id = :user AND device_id = :device",
                mapOf("id" to id, "user" to userId, "device" to deviceId),
                inquiryMapper,
            ).firstOrNull()

    /** Atomically marks the inquiry used; false when another request got there first. */
    fun consume(
        id: UUID,
        now: Instant,
    ): Boolean =
        jdbc.update(
            "UPDATE payment_inquiries SET consumed_at = :now WHERE id = :id AND consumed_at IS NULL AND expires_at > :now",
            mapOf("id" to id, "now" to Timestamp.from(now)),
        ) == 1

    fun findByIdempotency(hash: String): StoredPayment? =
        jdbc
            .query(
                "SELECT inquiry_id, transaction_id FROM payments WHERE idempotency_hash = :hash",
                mapOf("hash" to hash),
            ) { rs, _ -> StoredPayment(rs.getObject(1, UUID::class.java), rs.getObject(2, UUID::class.java)) }
            .firstOrNull()

    fun insertPayment(
        userId: UUID,
        inquiryId: UUID,
        idempotencyHash: String,
        journalEntryId: UUID,
        transactionId: UUID,
    ) {
        jdbc.update(
            """
            INSERT INTO payments (id, user_id, inquiry_id, idempotency_hash, journal_entry_id, transaction_id)
            VALUES (:id, :user, :inquiry, :hash, :entry, :tx)
            """,
            mapOf(
                "id" to UUID.randomUUID(),
                "user" to userId,
                "inquiry" to inquiryId,
                "hash" to idempotencyHash,
                "entry" to journalEntryId,
                "tx" to transactionId,
            ),
        )
    }

    fun payerTransaction(
        journalEntryId: UUID,
        accountId: UUID,
    ): UUID =
        checkNotNull(
            jdbc.queryForObject(
                "SELECT id FROM transactions WHERE journal_entry_id = :entry AND account_id = :account AND amount_satang < 0",
                mapOf("entry" to journalEntryId, "account" to accountId),
                UUID::class.java,
            ),
        )

    /** Transfers to other people today (Thai day); own-account moves do not count (TRF-08). */
    fun transferredToday(
        accountId: UUID,
        today: LocalDate,
    ): Long =
        jdbc.queryForObject(
            """
            SELECT COALESCE(SUM(i.amount_satang), 0) FROM payments p JOIN payment_inquiries i ON i.id = p.inquiry_id
            WHERE i.from_account_id = :account AND i.kind = 'transfer' AND i.recipient_type <> 'own' AND p.created_at >= :start
            """,
            mapOf("account" to accountId, "start" to Timestamp.from(today.atStartOfDay(BankTime.ZONE).toInstant())),
            Long::class.java,
        ) ?: 0L

    fun lockAccount(accountId: UUID) {
        jdbc.query("SELECT id FROM accounts WHERE id = :id FOR UPDATE", mapOf("id" to accountId)) { _, _ -> }
    }

    /** Slip data for a payer's history row, or null when the row is not a payment by this customer. */
    fun slipRow(
        userId: UUID,
        transactionId: UUID,
    ): SlipRow? =
        jdbc
            .query(
                """
                SELECT i.*, j.reference_no, t.occurred_at, a.account_number AS from_number, u.first_name_th, u.first_name_en,
                       u.last_name_th, u.last_name_en
                FROM payments p
                JOIN payment_inquiries i ON i.id = p.inquiry_id
                JOIN journal_entries j ON j.id = p.journal_entry_id
                JOIN transactions t ON t.id = p.transaction_id
                JOIN accounts a ON a.id = i.from_account_id
                JOIN users u ON u.id = p.user_id
                WHERE p.transaction_id = :tx AND p.user_id = :user
                """,
                mapOf("tx" to transactionId, "user" to userId),
            ) { rs, n ->
                SlipRow(
                    inquiry = checkNotNull(inquiryMapper.mapRow(rs, n)),
                    transactionId = transactionId,
                    referenceNo = rs.getString("reference_no"),
                    occurredAt = rs.getTimestamp("occurred_at").toInstant(),
                    fromAccountNumber = rs.getString("from_number"),
                    payerTh = "${rs.getString("first_name_th")} ${rs.getString("last_name_th")}",
                    payerEn = "${rs.getString("first_name_en")} ${rs.getString("last_name_en")}",
                )
            }.firstOrNull()
}

data class SlipRow(
    val inquiry: Inquiry,
    val transactionId: UUID,
    val referenceNo: String,
    val occurredAt: Instant,
    val fromAccountNumber: String,
    val payerTh: String,
    val payerEn: String,
)
