package com.luxebank.cards

import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import java.util.UUID

data class CardRow(
    val id: UUID,
    val userId: UUID,
    val accountId: UUID,
    val type: String,
    val productName: String,
    val last4: String,
    val tokenRef: String,
    val expiryMonth: Int,
    val expiryYear: Int,
    val status: String,
    val dailyLimitSatang: Long,
    val maxDailyLimitSatang: Long,
    val online: Boolean,
    val overseas: Boolean,
    val contactless: Boolean,
    val atm: Boolean,
    val rewardPoints: Long,
    val travelInsurance: Boolean,
    /** Linked deposit account's balance (debit) or the card account's balance, negative while owed (credit). */
    val accountBalanceSatang: Long,
    val creditLimitSatang: Long,
    val accountNumber: String,
) {
    val isCredit: Boolean get() = type == "credit"
}

data class NewCard(
    val userId: UUID,
    val accountId: UUID,
    val credit: Boolean,
    val productName: String,
    val last4: String,
    val tokenRef: String,
    val expiryMonth: Int,
    val expiryYear: Int,
    val dailyLimitSatang: Long,
    val maxDailyLimitSatang: Long,
    val online: Boolean = true,
    val overseas: Boolean = false,
    val contactless: Boolean = true,
    val atm: Boolean = true,
    val rewardPoints: Long = 0,
    val travelInsurance: Boolean = false,
)

data class CardControls(
    val online: Boolean,
    val overseas: Boolean,
    val contactless: Boolean,
    val atm: Boolean,
    val dailyLimitSatang: Long,
)

/** Cards scoped to their owner; another customer's card reads as missing (13.1 A01). */
@Repository
class CardStore(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val mapper =
        RowMapper { rs, _ ->
            CardRow(
                id = rs.getObject("id", UUID::class.java),
                userId = rs.getObject("user_id", UUID::class.java),
                accountId = rs.getObject("account_id", UUID::class.java),
                type = rs.getString("type"),
                productName = rs.getString("product_name"),
                last4 = rs.getString("last4"),
                tokenRef = rs.getString("token_ref"),
                expiryMonth = rs.getInt("expiry_month"),
                expiryYear = rs.getInt("expiry_year"),
                status = rs.getString("status"),
                dailyLimitSatang = rs.getLong("daily_limit_satang"),
                maxDailyLimitSatang = rs.getLong("max_daily_limit_satang"),
                online = rs.getBoolean("online_enabled"),
                overseas = rs.getBoolean("overseas_enabled"),
                contactless = rs.getBoolean("contactless_enabled"),
                atm = rs.getBoolean("atm_enabled"),
                rewardPoints = rs.getLong("reward_points"),
                travelInsurance = rs.getBoolean("travel_insurance"),
                accountBalanceSatang = rs.getLong("balance_satang"),
                creditLimitSatang = rs.getLong("credit_limit_satang"),
                accountNumber = rs.getString("account_number"),
            )
        }

    private val select =
        """
        SELECT c.*, a.balance_satang, a.credit_limit_satang, a.account_number
        FROM cards c JOIN accounts a ON a.id = c.account_id
        """

    /** Cards the customer can still use or unfreeze; lost and closed cards drop out. */
    fun listForUser(userId: UUID): List<CardRow> =
        jdbc.query(
            "$select WHERE c.user_id = :user AND c.status IN ('active', 'frozen') ORDER BY c.type DESC, c.created_at, c.id",
            mapOf("user" to userId),
            mapper,
        )

    fun findOwned(
        userId: UUID,
        id: UUID,
    ): CardRow? = jdbc.query("$select WHERE c.id = :id AND c.user_id = :user", mapOf("id" to id, "user" to userId), mapper).firstOrNull()

    fun lockOwned(
        userId: UUID,
        id: UUID,
    ): CardRow? =
        jdbc
            .query("SELECT id FROM cards WHERE id = :id AND user_id = :user FOR UPDATE", mapOf("id" to id, "user" to userId)) { rs, _ ->
                rs.getObject(1, UUID::class.java)
            }.firstOrNull()
            ?.let { findOwned(userId, it) }

    fun insert(card: NewCard): UUID {
        val id = UUID.randomUUID()
        jdbc.update(
            """
            INSERT INTO cards (id, user_id, account_id, type, product_name, last4, token_ref, expiry_month, expiry_year,
                daily_limit_satang, max_daily_limit_satang, online_enabled, overseas_enabled, contactless_enabled, atm_enabled,
                reward_points, travel_insurance)
            VALUES (:id, :user, :account, :type, :product, :last4, :token, :month, :year, :daily, :maxDaily, :online, :overseas,
                :contactless, :atm, :points, :insurance)
            """,
            mapOf(
                "id" to id,
                "user" to card.userId,
                "account" to card.accountId,
                "type" to if (card.credit) "credit" else "debit",
                "product" to card.productName,
                "last4" to card.last4,
                "token" to card.tokenRef,
                "month" to card.expiryMonth,
                "year" to card.expiryYear,
                "daily" to card.dailyLimitSatang,
                "maxDaily" to card.maxDailyLimitSatang,
                "online" to card.online,
                "overseas" to card.overseas,
                "contactless" to card.contactless,
                "atm" to card.atm,
                "points" to card.rewardPoints,
                "insurance" to card.travelInsurance,
            ),
        )
        return id
    }

    fun setStatus(
        id: UUID,
        status: String,
        replacedBy: UUID? = null,
    ) {
        jdbc.update(
            "UPDATE cards SET status = :status, replaced_by = COALESCE(:replacedBy, replaced_by), version = version + 1 WHERE id = :id",
            mapOf("id" to id, "status" to status, "replacedBy" to replacedBy),
        )
    }

    fun setControls(
        id: UUID,
        controls: CardControls,
    ) {
        jdbc.update(
            """
            UPDATE cards SET online_enabled = :online, overseas_enabled = :overseas, contactless_enabled = :contactless,
                atm_enabled = :atm, daily_limit_satang = :daily, version = version + 1
            WHERE id = :id
            """,
            mapOf(
                "id" to id,
                "online" to controls.online,
                "overseas" to controls.overseas,
                "contactless" to controls.contactless,
                "atm" to controls.atm,
                "daily" to controls.dailyLimitSatang,
            ),
        )
    }

    /** The card and every card it replaced, so a replacement keeps its history (CARD-04, CARD-09). */
    fun lineage(id: UUID): List<UUID> =
        jdbc.query(
            """
            WITH RECURSIVE chain(id) AS (
                SELECT CAST(:id AS UUID)
                UNION SELECT c.id FROM cards c JOIN chain ON c.replaced_by = chain.id
            )
            SELECT id FROM chain
            """,
            mapOf("id" to id),
        ) { rs, _ -> rs.getObject(1, UUID::class.java) }
}
