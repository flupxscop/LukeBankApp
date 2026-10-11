package com.luxebank.payments

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import jakarta.validation.Valid
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Instant
import java.util.UUID

data class Payee(
    val id: UUID,
    val type: RecipientType,
    val bankCode: String,
    val accountOrProxy: String,
    val name: String,
    val nickname: String?,
    val favorite: Boolean,
    val lastUsedAt: Instant,
)

/** Favourites and recent recipients (TRF-11). Full numbers stay on the server; clients pay a payee by its id. */
@Repository
class PayeeStore(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val mapper =
        RowMapper { rs, _ ->
            Payee(
                id = rs.getObject("id", UUID::class.java),
                type = RecipientType.valueOf(rs.getString("type").uppercase()),
                bankCode = rs.getString("bank_code"),
                accountOrProxy = rs.getString("account_or_proxy"),
                name = rs.getString("name"),
                nickname = rs.getString("nickname"),
                favorite = rs.getBoolean("favorite"),
                lastUsedAt = rs.getTimestamp("last_used_at").toInstant(),
            )
        }

    /** Records a completed transfer; once a favourite, always a favourite until the customer says otherwise. */
    fun remember(
        inquiry: Inquiry,
        favorite: Boolean,
    ) {
        if (inquiry.recipientType !in setOf(RecipientType.INTERNAL, RecipientType.OTHER_BANK, RecipientType.PROMPTPAY)) return
        jdbc.update(
            """
            INSERT INTO payees (id, user_id, type, bank_code, account_or_proxy, name, favorite, last_used_at)
            VALUES (:id, :user, :type, :bank, :account, :name, :favorite, now())
            ON CONFLICT (user_id, type, bank_code, account_or_proxy)
            DO UPDATE SET last_used_at = now(), name = EXCLUDED.name, favorite = payees.favorite OR EXCLUDED.favorite
            """,
            mapOf(
                "id" to UUID.randomUUID(),
                "user" to inquiry.userId,
                "type" to inquiry.recipientType.code,
                "bank" to if (inquiry.recipientType == RecipientType.PROMPTPAY) PROMPTPAY_BANK else inquiry.bankCode,
                "account" to inquiry.accountOrProxy,
                "name" to inquiry.recipientName,
                "favorite" to favorite,
            ),
        )
    }

    fun list(userId: UUID): List<Payee> =
        jdbc.query(
            "SELECT * FROM payees WHERE user_id = :user ORDER BY favorite DESC, last_used_at DESC LIMIT 20",
            mapOf("user" to userId),
            mapper,
        )

    fun findOwned(
        userId: UUID,
        id: UUID,
    ): Payee? =
        jdbc.query("SELECT * FROM payees WHERE id = :id AND user_id = :user", mapOf("id" to id, "user" to userId), mapper).firstOrNull()

    fun update(
        userId: UUID,
        id: UUID,
        favorite: Boolean,
        nickname: String?,
    ): Boolean =
        jdbc.update(
            "UPDATE payees SET favorite = :favorite, nickname = :nickname WHERE id = :id AND user_id = :user",
            mapOf("id" to id, "user" to userId, "favorite" to favorite, "nickname" to nickname),
        ) == 1

    fun delete(
        userId: UUID,
        id: UUID,
    ): Boolean = jdbc.update("DELETE FROM payees WHERE id = :id AND user_id = :user", mapOf("id" to id, "user" to userId)) == 1

    companion object {
        /** Bank column for PromptPay payees: the proxy is the identity, whichever bank it points at today. */
        const val PROMPTPAY_BANK = "PP"
    }
}

data class PayeeResponse(
    val id: UUID,
    val type: String,
    val name: String,
    val nickname: String?,
    val bankCode: String?,
    val bankName: String?,
    val account: String,
    val favorite: Boolean,
    val lastUsedAt: Instant,
) {
    companion object {
        fun of(
            payee: Payee,
            english: Boolean,
        ): PayeeResponse {
            val bank = Bank.of(payee.bankCode)
            return PayeeResponse(
                id = payee.id,
                type = payee.type.code,
                name = Masking.name(payee.name),
                nickname = payee.nickname,
                bankCode = bank?.code,
                bankName = bank?.name(english),
                account = Masking.account(payee.accountOrProxy),
                favorite = payee.favorite,
                lastUsedAt = payee.lastUsedAt,
            )
        }
    }
}

data class UpdatePayeeRequest(
    val favorite: Boolean,
    @field:Size(max = 40)
    @field:Pattern(regexp = "^[^\\p{Cntrl}]*$")
    val nickname: String? = null,
)

@RestController
@RequestMapping("/api/v1/payees")
class PayeesController(
    private val payees: PayeeStore,
    private val audit: AuditService,
) {
    @GetMapping
    fun list(
        current: CurrentDevice,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): List<PayeeResponse> = payees.list(current.userId).map { PayeeResponse.of(it, language.isEnglish()) }

    @PutMapping("/{id}")
    @Transactional
    fun update(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @Valid @RequestBody request: UpdatePayeeRequest,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): PayeeResponse {
        val nickname = request.nickname?.trim()?.ifEmpty { null }
        if (!payees.update(current.userId, id, request.favorite, nickname)) throw notFound()
        return PayeeResponse.of(checkNotNull(payees.findOwned(current.userId, id)), language.isEnglish())
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    fun delete(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ) {
        if (!payees.delete(current.userId, id)) throw notFound()
        audit.record(AuditAction.PAYEE_DELETED, current.userId, current.deviceId, mapOf("payeeId" to id.toString()))
    }

    private fun notFound() = ApiException(ErrorCode.NOT_FOUND, "Resource not found")
}
