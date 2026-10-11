package com.luxebank.accounts

import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.Money
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.util.UUID

data class AccountRow(
    val id: UUID,
    val userId: UUID,
    val type: String,
    val name: String,
    val accountNumber: String,
    val primary: Boolean,
    val balanceSatang: Long,
) {
    /** "•••• 4289" — the full account number never leaves the server on list screens. */
    val maskedNumber: String get() = "•••• " + accountNumber.takeLast(MASK_VISIBLE)

    private companion object {
        const val MASK_VISIBLE = 4
    }
}

data class AccountResponse(
    val id: UUID,
    val name: String,
    val maskedNumber: String,
    val type: String,
    val primary: Boolean,
    val balance: String,
) {
    companion object {
        fun of(row: AccountRow) =
            AccountResponse(row.id, row.name, row.maskedNumber, row.type, row.primary, Money.format(row.balanceSatang))
    }
}

/** Customer accounts. Every lookup is scoped to the owner, so other customers' IDs read as not found (13.1 A01). */
@Repository
class AccountQueries(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val mapper =
        RowMapper { rs, _ ->
            AccountRow(
                id = rs.getObject("id", UUID::class.java),
                userId = rs.getObject("user_id", UUID::class.java),
                type = rs.getString("type"),
                name = rs.getString("name"),
                accountNumber = rs.getString("account_number"),
                primary = rs.getBoolean("is_primary"),
                balanceSatang = rs.getLong("balance_satang"),
            )
        }

    fun listForUser(userId: UUID): List<AccountRow> =
        jdbc.query(
            "SELECT * FROM accounts WHERE user_id = :user AND status <> 'closed' ORDER BY is_primary DESC, created_at, id",
            mapOf("user" to userId),
            mapper,
        )

    fun findOwned(
        userId: UUID,
        accountId: UUID,
    ): AccountRow? =
        jdbc
            .query(
                "SELECT * FROM accounts WHERE id = :id AND user_id = :user AND status <> 'closed'",
                mapOf("id" to accountId, "user" to userId),
                mapper,
            ).firstOrNull()

    fun requireOwned(
        userId: UUID,
        accountId: UUID,
    ): AccountRow = findOwned(userId, accountId) ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    fun requirePrimary(userId: UUID): AccountRow =
        listForUser(userId).firstOrNull() ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
}

@RestController
@RequestMapping("/api/v1/accounts")
class AccountsController(
    private val accounts: AccountQueries,
) {
    @GetMapping
    fun list(current: CurrentDevice): List<AccountResponse> = accounts.listForUser(current.userId).map(AccountResponse::of)
}
