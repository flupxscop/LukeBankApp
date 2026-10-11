package com.luxebank.users

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.notifications.NotificationStore
import jakarta.validation.Valid
import jakarta.validation.constraints.Pattern
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Instant
import java.util.UUID

data class RelationshipManagerResponse(
    val name: String,
    val phone: String,
    val hours: String,
)

/** Security alerts are always on (NOTI-02), so they are reported but cannot be changed. */
data class PreferencesResponse(
    val language: String,
    val notifyTransactions: Boolean,
    val notifyMarketing: Boolean,
    val notifySecurity: Boolean = true,
)

data class MeResponse(
    val firstName: String,
    val lastName: String,
    val tier: String,
    val maskedPhone: String,
    val relationshipManager: RelationshipManagerResponse?,
    val preferences: PreferencesResponse,
    val unreadNotifications: Int,
)

data class PreferencesRequest(
    @field:Pattern(regexp = "th|en") val language: String? = null,
    val notifyTransactions: Boolean? = null,
    val notifyMarketing: Boolean? = null,
)

data class DeviceResponse(
    val id: UUID,
    val name: String,
    val registeredAt: Instant,
    val revokedAt: Instant?,
    val current: Boolean,
    val biometricEnabled: Boolean,
)

data class PushTokenRequest(
    /** APNs tokens are 64 hex characters today; allow some room for other providers. */
    @field:Pattern(regexp = "[A-Za-z0-9:_-]{16,200}") val token: String,
)

@Repository
class ProfileStore(
    private val jdbc: NamedParameterJdbcTemplate,
) {
    fun relationshipManager(
        userId: UUID,
        english: Boolean,
    ): RelationshipManagerResponse? =
        jdbc
            .query(
                """
                SELECT rm.* FROM relationship_managers rm JOIN users u ON u.relationship_manager_id = rm.id WHERE u.id = :user
                """,
                mapOf("user" to userId),
            ) { rs, _ ->
                RelationshipManagerResponse(
                    name = rs.getString(if (english) "name_en" else "name_th"),
                    phone = rs.getString("phone"),
                    hours = rs.getString(if (english) "hours_en" else "hours_th"),
                )
            }.firstOrNull()

    fun preferences(userId: UUID): PreferencesResponse =
        jdbc
            .query(
                "SELECT preferred_language, notify_transactions, notify_marketing FROM users WHERE id = :user",
                mapOf("user" to userId),
            ) { rs, _ ->
                PreferencesResponse(
                    rs.getString("preferred_language"),
                    rs.getBoolean("notify_transactions"),
                    rs.getBoolean("notify_marketing"),
                )
            }.firstOrNull() ?: throw ApiException(ErrorCode.NOT_FOUND, "Resource not found")

    fun updatePreferences(
        userId: UUID,
        request: PreferencesRequest,
    ) {
        jdbc.update(
            """
            UPDATE users SET
                preferred_language = COALESCE(:language, preferred_language),
                notify_transactions = COALESCE(:transactions, notify_transactions),
                notify_marketing = COALESCE(:marketing, notify_marketing)
            WHERE id = :user
            """,
            mapOf(
                "user" to userId,
                "language" to request.language,
                "transactions" to request.notifyTransactions,
                "marketing" to request.notifyMarketing,
            ),
        )
    }

    /** The bound device plus the last few it replaced (PROF-06). */
    fun devices(
        userId: UUID,
        currentDevice: UUID,
    ): List<DeviceResponse> =
        jdbc.query(
            """
            SELECT id, device_name, registered_at, revoked_at, biometric_public_key IS NOT NULL AS biometric
            FROM devices WHERE user_id = :user ORDER BY revoked_at IS NULL DESC, registered_at DESC LIMIT $DEVICE_HISTORY
            """,
            mapOf("user" to userId),
        ) { rs, _ ->
            val id = rs.getObject("id", UUID::class.java)
            DeviceResponse(
                id = id,
                name = rs.getString("device_name"),
                registeredAt = rs.getTimestamp("registered_at").toInstant(),
                revokedAt = rs.getTimestamp("revoked_at")?.toInstant(),
                current = id == currentDevice,
                biometricEnabled = rs.getBoolean("biometric"),
            )
        }

    fun setPushToken(
        deviceId: UUID,
        token: String,
    ) {
        // A token belongs to one phone: clear it from any other row first (e.g. after re-registration).
        jdbc.update(
            "UPDATE devices SET push_token = NULL WHERE push_token = :token AND id <> :device",
            mapOf(
                "token" to token,
                "device" to deviceId,
            ),
        )
        jdbc.update(
            "UPDATE devices SET push_token = :token WHERE id = :device AND revoked_at IS NULL",
            mapOf(
                "token" to token,
                "device" to deviceId,
            ),
        )
    }

    private companion object {
        const val DEVICE_HISTORY = 5
    }
}

@Service
class ProfileService(
    private val users: UserRepository,
    private val store: ProfileStore,
    private val notifications: NotificationStore,
    private val audit: AuditService,
) {
    @Transactional(readOnly = true)
    fun me(
        userId: UUID,
        english: Boolean,
    ): MeResponse {
        val user = users.findById(userId).orElseThrow { ApiException(ErrorCode.NOT_FOUND, "Resource not found") }
        return MeResponse(
            firstName = if (english) user.firstNameEn else user.firstNameTh,
            lastName = if (english) user.lastNameEn else user.lastNameTh,
            tier = user.tier,
            maskedPhone = user.maskedPhone,
            relationshipManager = store.relationshipManager(userId, english),
            preferences = store.preferences(userId),
            unreadNotifications = notifications.unreadCount(userId),
        )
    }

    @Transactional
    fun updatePreferences(
        current: CurrentDevice,
        request: PreferencesRequest,
    ): PreferencesResponse {
        store.updatePreferences(current.userId, request)
        audit.record(
            AuditAction.PREFERENCES_CHANGED,
            current.userId,
            current.deviceId,
            listOfNotNull(
                request.language?.let { "language" to it },
                request.notifyTransactions?.let { "notifyTransactions" to it },
                request.notifyMarketing?.let { "notifyMarketing" to it },
            ).toMap(),
        )
        return store.preferences(current.userId)
    }

    @Transactional
    fun registerPushToken(
        current: CurrentDevice,
        token: String,
    ) {
        store.setPushToken(current.deviceId, token)
        audit.record(AuditAction.PUSH_TOKEN_REGISTERED, current.userId, current.deviceId)
    }
}

/** PROF-01…07. */
@RestController
@RequestMapping("/api/v1/me")
class MeController(
    private val service: ProfileService,
    private val store: ProfileStore,
) {
    @GetMapping
    fun me(
        current: CurrentDevice,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): MeResponse = service.me(current.userId, english = language?.startsWith("en") == true)

    @PatchMapping("/preferences")
    fun preferences(
        current: CurrentDevice,
        @Valid @RequestBody request: PreferencesRequest,
    ): PreferencesResponse = service.updatePreferences(current, request)

    @GetMapping("/devices")
    fun devices(current: CurrentDevice): List<DeviceResponse> = store.devices(current.userId, current.deviceId)

    @PutMapping("/devices/current/push-token")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun pushToken(
        current: CurrentDevice,
        @Valid @RequestBody request: PushTokenRequest,
    ) {
        service.registerPushToken(current, request.token)
    }
}
