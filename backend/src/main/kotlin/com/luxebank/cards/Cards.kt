package com.luxebank.cards

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.auth.StepUpProof
import com.luxebank.auth.StepUpVerifier
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.integration.CardProcessor
import com.luxebank.integration.CardRules
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Money
import com.luxebank.notifications.SecurityEvent
import com.luxebank.notifications.SecurityEventType
import com.luxebank.transactions.Cursor
import com.luxebank.transactions.TransactionPageResponse
import com.luxebank.transactions.TransactionQueries
import com.luxebank.transactions.TransactionResponse
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.context.ApplicationEventPublisher
import org.springframework.http.CacheControl
import org.springframework.http.ResponseEntity
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Clock
import java.time.LocalDate
import java.util.UUID

data class CreditSummary(
    val limit: String,
    val used: String,
    val available: String,
    val minimumPayment: String,
    val dueDate: LocalDate?,
)

data class CardChannels(
    val online: Boolean,
    val overseas: Boolean,
    val contactless: Boolean,
    val atm: Boolean,
)

data class CardResponse(
    val id: UUID,
    val type: String,
    val productName: String,
    val last4: String,
    val expiry: String,
    val status: String,
    val channels: CardChannels,
    val dailyLimit: String,
    val maxDailyLimit: String,
    val rewardPoints: Long,
    val travelInsurance: Boolean,
    /** Credit cards only (CARD-02). */
    val credit: CreditSummary?,
    /** Debit cards only: the account the card spends from. */
    val linkedAccount: String?,
    val linkedBalance: String?,
)

data class ControlsRequest(
    val online: Boolean? = null,
    val overseas: Boolean? = null,
    val contactless: Boolean? = null,
    val atm: Boolean? = null,
    val dailyLimit: String? = null,
)

data class SensitiveResponse(
    val pan: String,
    val cvv: String,
    val expiry: String,
    /** The app hides the details after this many seconds (CARD-07). */
    val visibleForSeconds: Int,
)

/** Cards (CARD-01…09). Simulated processor behind [CardProcessor]; LuxeBank never stores PAN or CVV. */
@Service
class CardService(
    private val cards: CardStore,
    private val processor: CardProcessor,
    private val stepUp: StepUpVerifier,
    private val audit: AuditService,
    private val tx: TransactionTemplate,
    private val clock: Clock,
    private val events: ApplicationEventPublisher,
) {
    @Transactional(readOnly = true)
    fun list(userId: UUID): List<CardResponse> = cards.listForUser(userId).map(::response)

    @Transactional(readOnly = true)
    fun detail(
        userId: UUID,
        id: UUID,
    ): CardResponse = response(require(userId, id))

    /** CARD-03: instant, reversible. */
    @Transactional
    fun setFrozen(
        current: CurrentDevice,
        id: UUID,
        frozen: Boolean,
    ): CardResponse {
        val card = cards.lockOwned(current.userId, id)?.takeIf { it.status in USABLE } ?: throw notFound()
        val status = if (frozen) "frozen" else "active"
        cards.setStatus(card.id, status)
        processor.applyRules(card.tokenRef, rules(card.copy(status = status)))
        audit.record(
            if (frozen) AuditAction.CARD_FROZEN else AuditAction.CARD_UNFROZEN,
            current.userId,
            current.deviceId,
            mapOf("cardId" to id.toString()),
        )
        events.publishEvent(
            SecurityEvent(current.userId, if (frozen) SecurityEventType.CARD_FROZEN else SecurityEventType.CARD_UNFROZEN, card.last4),
        )
        return detail(current.userId, id)
    }

    /** CARD-05, CARD-06: channels and a daily limit up to what the bank approved. */
    @Transactional
    fun updateControls(
        current: CurrentDevice,
        id: UUID,
        request: ControlsRequest,
    ): CardResponse {
        val card = cards.lockOwned(current.userId, id)?.takeIf { it.status in USABLE } ?: throw notFound()
        val daily = request.dailyLimit?.let { Money.parsePositive(it) ?: invalid() } ?: card.dailyLimitSatang
        if (daily > card.maxDailyLimitSatang) invalid()
        val controls =
            CardControls(
                online = request.online ?: card.online,
                overseas = request.overseas ?: card.overseas,
                contactless = request.contactless ?: card.contactless,
                atm = request.atm ?: card.atm,
                dailyLimitSatang = daily,
            )
        cards.setControls(card.id, controls)
        val updated = checkNotNull(cards.findOwned(current.userId, id))
        processor.applyRules(updated.tokenRef, rules(updated))
        audit.record(
            AuditAction.CARD_CONTROLS_CHANGED,
            current.userId,
            current.deviceId,
            mapOf("cardId" to id.toString(), "controls" to controls.toString()),
        )
        return response(updated)
    }

    /**
     * CARD-04: block the card for good and issue a replacement with the same settings. Needs the PIN with a
     * device signature; history, points and the linked account carry over to the new card.
     * The proof is checked before the card transaction opens, so no request ever holds two connections.
     */
    fun reportLost(
        current: CurrentDevice,
        id: UUID,
        proof: StepUpProof,
    ): CardResponse {
        val lost = cards.findOwned(current.userId, id)?.takeIf { it.status in USABLE } ?: throw notFound()
        stepUp.verify(current, proof, requireBiometric = false)
        val replacement = checkNotNull(tx.execute { replace(current.userId, id) })
        audit.record(
            AuditAction.CARD_REPORTED_LOST,
            current.userId,
            current.deviceId,
            mapOf("cardId" to id.toString(), "replacementId" to replacement.toString()),
        )
        events.publishEvent(SecurityEvent(current.userId, SecurityEventType.CARD_REPORTED_LOST, lost.last4))
        return detail(current.userId, replacement)
    }

    private fun replace(
        userId: UUID,
        id: UUID,
    ): UUID {
        val card = cards.lockOwned(userId, id)?.takeIf { it.status in USABLE } ?: throw notFound()
        processor.block(card.tokenRef)
        val issued = processor.issue(card.isCredit, card.productName)
        val replacement =
            cards.insert(
                NewCard(
                    userId = card.userId,
                    accountId = card.accountId,
                    credit = card.isCredit,
                    productName = card.productName,
                    last4 = issued.last4,
                    tokenRef = issued.tokenRef,
                    expiryMonth = issued.expiryMonth,
                    expiryYear = issued.expiryYear,
                    dailyLimitSatang = card.dailyLimitSatang,
                    maxDailyLimitSatang = card.maxDailyLimitSatang,
                    online = card.online,
                    overseas = card.overseas,
                    contactless = card.contactless,
                    atm = card.atm,
                    rewardPoints = card.rewardPoints,
                    travelInsurance = card.travelInsurance,
                ),
            )
        cards.setStatus(card.id, "lost", replacedBy = replacement)
        processor.applyRules(issued.tokenRef, rules(checkNotNull(cards.findOwned(userId, replacement))))
        return replacement
    }

    /** CARD-07: full number and CVV after Face ID; fetched from the processor, never stored or cached. */
    fun reveal(
        current: CurrentDevice,
        id: UUID,
        proof: StepUpProof,
    ): SensitiveResponse {
        val card = cards.findOwned(current.userId, id)?.takeIf { it.status in USABLE } ?: throw notFound()
        stepUp.verify(current, proof, requireBiometric = true)
        val secrets = processor.reveal(card.tokenRef)
        audit.record(AuditAction.CARD_DETAILS_VIEWED, current.userId, current.deviceId, mapOf("cardId" to id.toString()))
        events.publishEvent(SecurityEvent(current.userId, SecurityEventType.CARD_DETAILS_VIEWED, card.last4))
        return SensitiveResponse(secrets.pan, secrets.cvv, expiry(card), VISIBLE_SECONDS)
    }

    private fun require(
        userId: UUID,
        id: UUID,
    ) = cards.findOwned(userId, id) ?: throw notFound()

    private fun response(card: CardRow): CardResponse =
        CardResponse(
            id = card.id,
            type = card.type,
            productName = card.productName,
            last4 = card.last4,
            expiry = expiry(card),
            status = card.status,
            channels = CardChannels(card.online, card.overseas, card.contactless, card.atm),
            dailyLimit = Money.format(card.dailyLimitSatang),
            maxDailyLimit = Money.format(card.maxDailyLimitSatang),
            rewardPoints = card.rewardPoints,
            travelInsurance = card.travelInsurance,
            credit = if (card.isCredit) credit(card) else null,
            linkedAccount = if (card.isCredit) null else "•••• " + card.accountNumber.takeLast(MASK_VISIBLE),
            linkedBalance = if (card.isCredit) null else Money.format(card.accountBalanceSatang),
        )

    /** Simulated statement: 10% of what is owed (at least ฿1,000), due on the 2nd of next month. */
    private fun credit(card: CardRow): CreditSummary {
        val used = (-card.accountBalanceSatang).coerceAtLeast(0)
        val minimum =
            if (used == 0L) {
                0L
            } else {
                BigDecimal(used)
                    .multiply(MINIMUM_RATE)
                    .setScale(0, RoundingMode.UP)
                    .toLong()
                    .coerceAtLeast(MINIMUM_PAYMENT)
                    .coerceAtMost(used)
            }
        val today = LocalDate.now(clock.withZone(BankTime.ZONE))
        return CreditSummary(
            limit = Money.format(card.creditLimitSatang),
            used = Money.format(used),
            available = Money.format(card.creditLimitSatang - used),
            minimumPayment = Money.format(minimum),
            dueDate = if (used == 0L) null else today.plusMonths(1).withDayOfMonth(DUE_DAY),
        )
    }

    private fun rules(card: CardRow) =
        CardRules(card.status == "active", card.online, card.overseas, card.contactless, card.atm, card.dailyLimitSatang)

    private fun expiry(card: CardRow) = "%02d/%02d".format(card.expiryMonth, card.expiryYear % CENTURY)

    private fun notFound() = ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    private fun invalid(): Nothing = throw ApiException(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    private companion object {
        val USABLE = setOf("active", "frozen")
        val MINIMUM_RATE: BigDecimal = BigDecimal("0.10")
        const val MINIMUM_PAYMENT = 100_000L
        const val DUE_DAY = 2
        const val MASK_VISIBLE = 4
        const val CENTURY = 100
        const val VISIBLE_SECONDS = 30
    }
}

@RestController
@RequestMapping("/api/v1/cards")
class CardsController(
    private val service: CardService,
    private val cards: CardStore,
    private val transactions: TransactionQueries,
) {
    @GetMapping
    fun list(current: CurrentDevice): List<CardResponse> = service.list(current.userId)

    @GetMapping("/{id}")
    fun detail(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ): CardResponse = service.detail(current.userId, id)

    /** CARD-09: purchases made with this card and the cards it replaced. */
    @GetMapping("/{id}/transactions")
    @Transactional(readOnly = true)
    fun transactions(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "20") @Min(1) @Max(MAX_PAGE) limit: Int,
    ): TransactionPageResponse {
        val card = cards.findOwned(current.userId, id) ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        val page = transactions.cardPage(cards.lineage(card.id), cursor?.let(Cursor::decode), limit)
        return TransactionPageResponse(page.items.map(TransactionResponse::of), page.nextCursor, null)
    }

    @PostMapping("/{id}/freeze")
    fun freeze(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ): CardResponse = service.setFrozen(current, id, frozen = true)

    @PostMapping("/{id}/unfreeze")
    fun unfreeze(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ): CardResponse = service.setFrozen(current, id, frozen = false)

    @PatchMapping("/{id}/controls")
    fun controls(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @Valid @RequestBody request: ControlsRequest,
    ): CardResponse = service.updateControls(current, id, request)

    @PostMapping("/{id}/report-lost")
    fun reportLost(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @Valid @RequestBody proof: StepUpProof,
    ): CardResponse = service.reportLost(current, id, proof)

    /** Card details must never be cached by the client or any proxy. */
    @PostMapping("/{id}/sensitive")
    fun sensitive(
        current: CurrentDevice,
        @PathVariable id: UUID,
        @Valid @RequestBody proof: StepUpProof,
    ): ResponseEntity<SensitiveResponse> =
        ResponseEntity
            .ok()
            .cacheControl(CacheControl.noStore())
            .header("Pragma", "no-cache")
            .body(service.reveal(current, id, proof))

    private companion object {
        const val MAX_PAGE = 50L
    }
}
