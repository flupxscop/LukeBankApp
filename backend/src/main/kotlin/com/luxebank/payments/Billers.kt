package com.luxebank.payments

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.BankTime
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import java.sql.Timestamp
import java.time.LocalDate
import java.util.UUID

data class Biller(
    val code: String,
    val nameTh: String,
    val nameEn: String,
    val category: String,
    val ref1LabelTh: String,
    val ref1LabelEn: String,
    val ref2LabelTh: String?,
    val ref2LabelEn: String?,
    val topUp: Boolean,
    val monogram: String,
) {
    fun name(english: Boolean) = if (english) nameEn else nameTh
}

data class SavedBill(
    val id: UUID,
    val billerCode: String,
    val ref1: String,
    val ref2: String,
    val nickname: String?,
)

/** Biller catalogue and the customer's saved bills (BILL-01, BILL-03). */
@Repository
class BillerCatalog(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val mapper =
        RowMapper { rs, _ ->
            Biller(
                code = rs.getString("code"),
                nameTh = rs.getString("name_th"),
                nameEn = rs.getString("name_en"),
                category = rs.getString("category"),
                ref1LabelTh = rs.getString("ref1_label_th"),
                ref1LabelEn = rs.getString("ref1_label_en"),
                ref2LabelTh = rs.getString("ref2_label_th"),
                ref2LabelEn = rs.getString("ref2_label_en"),
                topUp = rs.getBoolean("top_up"),
                monogram = rs.getString("monogram"),
            )
        }

    private val savedMapper =
        RowMapper { rs, _ ->
            SavedBill(
                rs.getObject("id", UUID::class.java),
                rs.getString("biller_code"),
                rs.getString("ref1"),
                rs.getString("ref2"),
                rs.getString("nickname"),
            )
        }

    fun list(category: String?): List<Biller> =
        jdbc.query(
            "SELECT * FROM billers WHERE (CAST(:category AS VARCHAR) IS NULL OR category = :category) ORDER BY top_up, name_en",
            mapOf("category" to category),
            mapper,
        )

    fun find(code: String): Biller? = jdbc.query("SELECT * FROM billers WHERE code = :code", mapOf("code" to code), mapper).firstOrNull()

    fun require(code: String): Biller = find(code) ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    fun findByQrId(qrBillerId: String): Biller? =
        jdbc.query("SELECT * FROM billers WHERE qr_biller_id = :id", mapOf("id" to qrBillerId), mapper).firstOrNull()

    fun save(
        userId: UUID,
        inquiry: Inquiry,
    ) {
        jdbc.update(
            """
            INSERT INTO saved_bills (id, user_id, biller_code, ref1, ref2) VALUES (:id, :user, :biller, :ref1, :ref2)
            ON CONFLICT (user_id, biller_code, ref1, ref2) DO NOTHING
            """,
            mapOf(
                "id" to UUID.randomUUID(),
                "user" to userId,
                "biller" to inquiry.billerCode,
                "ref1" to inquiry.ref1,
                "ref2" to inquiry.ref2.orEmpty(),
            ),
        )
    }

    fun saved(userId: UUID): List<SavedBill> =
        jdbc.query("SELECT * FROM saved_bills WHERE user_id = :user ORDER BY created_at", mapOf("user" to userId), savedMapper)

    fun findSaved(
        userId: UUID,
        id: UUID,
    ): SavedBill? =
        jdbc
            .query(
                "SELECT * FROM saved_bills WHERE id = :id AND user_id = :user",
                mapOf("id" to id, "user" to userId),
                savedMapper,
            ).firstOrNull()

    fun deleteSaved(
        userId: UUID,
        id: UUID,
    ): Boolean = jdbc.update("DELETE FROM saved_bills WHERE id = :id AND user_id = :user", mapOf("id" to id, "user" to userId)) == 1

    /** Whether the customer already paid this bill since the start of [month]'s billing cycle. */
    fun paidSince(
        userId: UUID,
        billerCode: String,
        ref1: String,
        since: LocalDate,
    ): Boolean =
        (
            jdbc.queryForObject(
                """
                SELECT COUNT(*) FROM payments p JOIN payment_inquiries i ON i.id = p.inquiry_id
                WHERE p.user_id = :user AND i.biller_code = :biller AND i.ref1 = :ref1 AND p.created_at >= :since
                """,
                mapOf(
                    "user" to userId,
                    "biller" to billerCode,
                    "ref1" to ref1,
                    "since" to Timestamp.from(since.atStartOfDay(BankTime.ZONE).toInstant()),
                ),
                Long::class.java,
            ) ?: 0L
        ) > 0
}
