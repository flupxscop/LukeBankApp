package com.luxebank.transactions

import com.luxebank.accounts.AccountQueries
import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.ledger.Category
import com.luxebank.ledger.Direction
import com.luxebank.ledger.Money
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.format.annotation.DateTimeFormat
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID

data class TransactionResponse(
    val id: UUID,
    val accountId: UUID,
    val merchant: String,
    val monogram: String?,
    val category: String,
    val channel: String,
    val occurredAt: Instant,
    val amount: String,
    val memo: String?,
) {
    companion object {
        fun of(row: TransactionRow) =
            TransactionResponse(
                id = row.id,
                accountId = row.accountId,
                merchant = row.merchant,
                monogram = row.monogram,
                category = row.category,
                channel = row.channel,
                occurredAt = row.occurredAt.truncatedTo(ChronoUnit.SECONDS),
                amount = Money.format(row.amountSatang),
                memo = row.memo,
            )
    }
}

data class TotalsResponse(
    val moneyIn: String,
    val moneyOut: String,
)

data class TransactionPageResponse(
    val items: List<TransactionResponse>,
    val nextCursor: String?,
    /** Totals for the whole filtered range; only on the first page. */
    val summary: TotalsResponse?,
)

data class TransactionAccount(
    val id: UUID,
    val name: String,
    val maskedNumber: String,
)

data class TransactionDetailResponse(
    val transaction: TransactionResponse,
    val referenceNo: String,
    val status: String,
    val account: TransactionAccount,
)

data class UpdateTransactionRequest(
    val category: String? = null,
    @field:Size(max = 100)
    @field:Pattern(regexp = "^[^\\p{Cntrl}]*$")
    val memo: String? = null,
    /** Explicitly clears the memo; `memo: null` alone leaves it unchanged. */
    val clearMemo: Boolean = false,
)

@RestController
@RequestMapping("/api/v1")
class TransactionsController(
    private val accounts: AccountQueries,
    private val transactions: TransactionQueries,
    private val audit: AuditService,
) {
    /** History with filters and cursor pagination (TXN-01…03). Another customer's account reads as 404 (BOLA). */
    @Suppress("LongParameterList") // one parameter per documented query filter
    @GetMapping("/accounts/{accountId}/transactions")
    @Transactional(readOnly = true)
    fun list(
        current: CurrentDevice,
        @PathVariable accountId: UUID,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "20") @Min(1) @Max(MAX_PAGE) limit: Int,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate?,
        @RequestParam(required = false) category: String?,
        @RequestParam(required = false) direction: String?,
        @RequestParam(required = false) @Size(max = MAX_QUERY) q: String?,
    ): TransactionPageResponse {
        val account = accounts.requireOwned(current.userId, accountId)
        if (from != null && to != null && from.isAfter(to)) invalid()
        val filter =
            TransactionFilter(
                from = from,
                to = to,
                category = category?.let { Category.parse(it) ?: invalid() },
                direction = direction?.let { Direction.parse(it) ?: invalid() },
                query = q,
            )
        val page = transactions.page(account.id, filter, cursor?.let(Cursor::decode), limit)
        val summary =
            if (cursor == null) {
                transactions.totals(account.id, filter).let { TotalsResponse(Money.format(it.inSatang), Money.format(it.outSatang)) }
            } else {
                null
            }
        return TransactionPageResponse(page.items.map(TransactionResponse::of), page.nextCursor, summary)
    }

    @GetMapping("/transactions/{id}")
    @Transactional(readOnly = true)
    fun detail(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ): TransactionDetailResponse = detailOf(requireOwned(current, id))

    /** Recategorise or annotate a transaction (TXN-05); the new category feeds spending insights. */
    @PatchMapping("/transactions/{id}")
    @Transactional
    fun update(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @Valid @RequestBody request: UpdateTransactionRequest,
    ): TransactionDetailResponse {
        requireOwned(current, id)
        val category = request.category?.let { Category.parse(it) ?: invalid() }
        val setMemo = request.clearMemo || request.memo != null
        val memo = if (request.clearMemo) null else request.memo?.trim()?.ifEmpty { null }
        if (category == null && !setMemo) invalid()
        transactions.update(id, category, setMemo, memo)
        audit.record(
            AuditAction.TRANSACTION_UPDATED,
            current.userId,
            current.deviceId,
            mapOf("transactionId" to id.toString(), "category" to category?.code, "memoChanged" to setMemo),
        )
        return detailOf(requireOwned(current, id))
    }

    private fun requireOwned(
        current: CurrentDevice,
        id: UUID,
    ) = transactions.findOwned(current.userId, id) ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    private fun detailOf(row: TransactionDetailRow) =
        TransactionDetailResponse(
            transaction = TransactionResponse.of(row.transaction),
            referenceNo = row.referenceNo,
            status = row.status,
            account = TransactionAccount(row.transaction.accountId, row.accountName, "•••• " + row.accountNumber.takeLast(MASK_VISIBLE)),
        )

    private fun invalid(): Nothing = throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    private companion object {
        const val MAX_PAGE = 50L
        const val MAX_QUERY = 50
        const val MASK_VISIBLE = 4
    }
}
