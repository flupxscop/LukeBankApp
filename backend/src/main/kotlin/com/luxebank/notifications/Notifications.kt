package com.luxebank.notifications

import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.integration.PushNotifier
import com.luxebank.transactions.Cursor
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.scheduling.annotation.Async
import org.springframework.scheduling.annotation.EnableAsync
import org.springframework.stereotype.Repository
import org.springframework.stereotype.Service
import org.springframework.transaction.event.TransactionalEventListener
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.sql.Timestamp
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Duration
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** Published by the ledger for every posting on a customer account (NOTI-01). */
data class TransactionPostedEvent(
    val accountId: UUID,
    val merchant: String,
    val amountSatang: Long,
    val occurredAt: Instant,
)

enum class SecurityEventType {
    NEW_DEVICE,
    PIN_CHANGED,
    BIOMETRIC_ENABLED,
    BIOMETRIC_DISABLED,
    CARD_FROZEN,
    CARD_UNFROZEN,
    CARD_REPORTED_LOST,
    CARD_DETAILS_VIEWED,
}

/** Published by auth and card services (NOTI-02). */
data class SecurityEvent(
    val userId: UUID,
    val type: SecurityEventType,
    /** Short non-sensitive detail, e.g. a card's last four digits. */
    val detail: String? = null,
)

enum class NotificationKind {
    TRANSACTION,
    SECURITY,
    MARKETING,
    ;

    val code: String get() = name.lowercase()
}

@Configuration
@EnableAsync
class AsyncConfig

/**
 * Turns events into inbox entries and push notifications (NOTI-01…03).
 * Runs after the business transaction commits and on another thread, so it never holds a second
 * connection while the request's own transaction is open (see the M3 review) and a failed push
 * never affects the payment.
 */
@Service
class NotificationService(
    private val store: NotificationStore,
    private val push: PushNotifier,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Async
    @TransactionalEventListener(fallbackExecution = true)
    fun on(event: TransactionPostedEvent) {
        // Backfills and simulated history are not news.
        if (event.occurredAt.isBefore(Instant.now().minus(RECENT))) return
        val owner = store.ownerOf(event.accountId) ?: return
        val english = owner.language == "en"
        val amount = "฿" + display(Math.absExact(event.amountSatang))
        val title =
            when {
                event.amountSatang > 0 -> if (english) "Money in $amount" else "เงินเข้า $amount"
                else -> if (english) "Money out $amount" else "เงินออก $amount"
            }
        val body = "${event.merchant} · ${if (english) "account" else "บัญชี"} x${owner.accountNumber.takeLast(LAST4)}"
        deliver(owner, NotificationKind.TRANSACTION, title, body, pushAllowed = owner.notifyTransactions)
    }

    @Async
    @TransactionalEventListener(fallbackExecution = true)
    fun on(event: SecurityEvent) {
        val owner = store.user(event.userId) ?: return
        val (title, body) = SecurityText.of(event, english = owner.language == "en")
        // NOTI-02: security alerts are always pushed.
        deliver(owner, NotificationKind.SECURITY, title, body, pushAllowed = true)
    }

    /** 150000 → "1,500.00" for people, unlike the API's plain decimal strings. */
    private fun display(satang: Long): String =
        DecimalFormat("#,##0.00", DecimalFormatSymbols(Locale.US)).format(BigDecimal.valueOf(satang, 2))

    private fun deliver(
        owner: Recipient,
        kind: NotificationKind,
        title: String,
        body: String,
        pushAllowed: Boolean,
    ) {
        store.insert(owner.userId, kind, title.take(TITLE_MAX), body.take(BODY_MAX))
        val token = owner.pushToken
        if (pushAllowed && token != null) {
            runCatching { push.send(token, title, body, kind.code) }
                .onFailure { log.warn("Push delivery failed for a {} notification", kind.code) }
        }
    }

    private companion object {
        val RECENT: Duration = Duration.ofHours(24)
        const val LAST4 = 4
        const val TITLE_MAX = 120
        const val BODY_MAX = 300
    }
}

/** Thai and English text for each security alert; `null` body means "show the card". */
private object SecurityText {
    private class Text(
        val th: String,
        val en: String,
        val bodyTh: String? = null,
        val bodyEn: String? = null,
    )

    private val texts =
        mapOf(
            SecurityEventType.NEW_DEVICE to
                Text(
                    "เข้าสู่ระบบจากเครื่องใหม่",
                    "New device signed in",
                    "หากไม่ใช่คุณ โปรดติดต่อธนาคารทันที",
                    "If this wasn't you, call LuxeBank right away.",
                ),
            SecurityEventType.PIN_CHANGED to
                Text("เปลี่ยน PIN แล้ว", "PIN changed", "PIN ของคุณถูกเปลี่ยนบนเครื่องนี้", "Your PIN was changed on this device."),
            SecurityEventType.BIOMETRIC_ENABLED to
                Text(
                    "เปิดใช้ Face ID แล้ว",
                    "Face ID turned on",
                    "ปลดล็อกและยืนยันรายการด้วย Face ID ได้แล้ว",
                    "You can now unlock and confirm with Face ID.",
                ),
            SecurityEventType.BIOMETRIC_DISABLED to
                Text(
                    "ปิด Face ID แล้ว",
                    "Face ID turned off",
                    "ใช้ PIN ในการปลดล็อกและยืนยันรายการ",
                    "Use your PIN to unlock and confirm.",
                ),
            SecurityEventType.CARD_FROZEN to Text("ระงับบัตรแล้ว", "Card frozen"),
            SecurityEventType.CARD_UNFROZEN to Text("เปิดใช้บัตรแล้ว", "Card unfrozen"),
            SecurityEventType.CARD_REPORTED_LOST to Text("ปิดบัตรและออกบัตรใหม่แล้ว", "Card blocked and replaced"),
            SecurityEventType.CARD_DETAILS_VIEWED to Text("มีการดูเลขบัตรเต็ม", "Card details viewed"),
        )

    fun of(
        event: SecurityEvent,
        english: Boolean,
    ): Pair<String, String> {
        val text = texts.getValue(event.type)
        val card = event.detail?.let { if (english) "card x$it" else "บัตร x$it" } ?: ""
        val body = (if (english) text.bodyEn else text.bodyTh) ?: card
        return (if (english) text.en else text.th) to body
    }
}

data class Recipient(
    val userId: UUID,
    val language: String,
    val notifyTransactions: Boolean,
    val notifyMarketing: Boolean,
    val pushToken: String?,
    val accountNumber: String = "",
)

data class NotificationRow(
    val id: UUID,
    val kind: String,
    val title: String,
    val body: String,
    val createdAt: Instant,
    val read: Boolean,
)

@Repository
class NotificationStore(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    private val recipient =
        RowMapper { rs, _ ->
            Recipient(
                userId = rs.getObject("id", UUID::class.java),
                language = rs.getString("preferred_language"),
                notifyTransactions = rs.getBoolean("notify_transactions"),
                notifyMarketing = rs.getBoolean("notify_marketing"),
                pushToken = rs.getString("push_token"),
                accountNumber = rs.getString("account_number") ?: "",
            )
        }

    private val select =
        """
        SELECT u.id, u.preferred_language, u.notify_transactions, u.notify_marketing, d.push_token, a.account_number
        FROM users u
        LEFT JOIN devices d ON d.user_id = u.id AND d.revoked_at IS NULL
        """

    fun user(userId: UUID): Recipient? =
        jdbc
            .query("$select LEFT JOIN accounts a ON FALSE WHERE u.id = :user", mapOf("user" to userId), recipient)
            .firstOrNull()

    fun ownerOf(accountId: UUID): Recipient? =
        jdbc
            .query("$select JOIN accounts a ON a.user_id = u.id WHERE a.id = :account", mapOf("account" to accountId), recipient)
            .firstOrNull()

    fun insert(
        userId: UUID,
        kind: NotificationKind,
        title: String,
        body: String,
    ) {
        jdbc.update(
            "INSERT INTO notifications (id, user_id, kind, title, body) VALUES (:id, :user, :kind, :title, :body)",
            mapOf("id" to UUID.randomUUID(), "user" to userId, "kind" to kind.code, "title" to title, "body" to body),
        )
    }

    fun page(
        userId: UUID,
        cursor: Cursor?,
        limit: Int,
    ): Pair<List<NotificationRow>, String?> {
        val params = mutableMapOf<String, Any?>("user" to userId, "limit" to limit + 1)
        var where = "user_id = :user"
        if (cursor != null) {
            where += " AND (created_at, id) < (:at, :id)"
            params["at"] = Timestamp.from(cursor.occurredAt)
            params["id"] = cursor.id
        }
        val rows =
            jdbc.query("SELECT * FROM notifications WHERE $where ORDER BY created_at DESC, id DESC LIMIT :limit", params) { rs, _ ->
                NotificationRow(
                    id = rs.getObject("id", UUID::class.java),
                    kind = rs.getString("kind"),
                    title = rs.getString("title"),
                    body = rs.getString("body"),
                    createdAt = rs.getTimestamp("created_at").toInstant(),
                    read = rs.getTimestamp("read_at") != null,
                )
            }
        val items = rows.take(limit)
        return items to if (rows.size > limit) items.last().let { Cursor(it.createdAt, it.id).encode() } else null
    }

    fun unreadCount(userId: UUID): Int =
        jdbc.queryForObject(
            "SELECT COUNT(*) FROM notifications WHERE user_id = :user AND read_at IS NULL",
            mapOf("user" to userId),
            Int::class.java,
        ) ?: 0

    fun exists(
        userId: UUID,
        id: UUID,
    ): Boolean =
        jdbc.queryForObject(
            "SELECT EXISTS (SELECT 1 FROM notifications WHERE user_id = :user AND id = :id)",
            mapOf("user" to userId, "id" to id),
            Boolean::class.java,
        ) == true

    fun markRead(
        userId: UUID,
        id: UUID?,
    ): Int =
        jdbc.update(
            """
            UPDATE notifications SET read_at = now()
            WHERE user_id = :user AND read_at IS NULL AND (CAST(:id AS UUID) IS NULL OR id = :id)
            """,
            mapOf("user" to userId, "id" to id),
        )
}

data class NotificationResponse(
    val id: UUID,
    val kind: String,
    val title: String,
    val body: String,
    val createdAt: Instant,
    val read: Boolean,
)

data class NotificationPage(
    val items: List<NotificationResponse>,
    val nextCursor: String?,
    val unreadCount: Int,
)

/** NOTI-03: the in-app inbox. */
@RestController
@RequestMapping("/api/v1/notifications")
class NotificationsController(
    private val store: NotificationStore,
) {
    @GetMapping
    fun list(
        current: CurrentDevice,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "20") @Min(1) @Max(MAX_PAGE) limit: Int,
    ): NotificationPage {
        val (rows, next) = store.page(current.userId, cursor?.let(Cursor::decode), limit)
        return NotificationPage(
            rows.map { NotificationResponse(it.id, it.kind, it.title, it.body, it.createdAt, it.read) },
            next,
            store.unreadCount(current.userId),
        )
    }

    @PostMapping("/read-all")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun readAll(current: CurrentDevice) {
        store.markRead(current.userId, null)
    }

    @PostMapping("/{id}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun read(
        current: CurrentDevice,
        @PathVariable id: UUID,
    ) {
        if (store.markRead(current.userId, id) == 0 && !store.exists(current.userId, id)) {
            throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")
        }
    }

    private companion object {
        const val MAX_PAGE = 50L
    }
}
