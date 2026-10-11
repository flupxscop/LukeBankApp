package com.luxebank.audit

import com.luxebank.common.tracing.TraceIdFilter
import org.slf4j.MDC
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.context.request.RequestContextHolder
import org.springframework.web.context.request.ServletRequestAttributes
import tools.jackson.databind.ObjectMapper
import java.security.MessageDigest
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.HexFormat
import java.util.UUID

enum class AuditAction {
    REGISTRATION_STARTED,
    REGISTRATION_FAILED,
    ACCOUNT_LOCKED,
    OTP_VERIFIED,
    OTP_FAILED,
    DEVICE_REGISTERED,
    DEVICE_REVOKED,
    LOGIN_SUCCEEDED,
    LOGIN_FAILED,
    PIN_LOCKED,
    PIN_CHANGED,
    BIOMETRIC_ENABLED,
    BIOMETRIC_DISABLED,
    TOKEN_REUSE_DETECTED,
    LOGGED_OUT,
    TRANSACTION_UPDATED,
    LEDGER_RECONCILIATION_FAILED,
    PAYMENT_SUCCEEDED,
    PAYMENT_FAILED,
    PAYMENT_AUTH_FAILED,
    PAYEE_DELETED,
}

/**
 * Append-only, hash-chained audit trail (spec 7.2, 13.1 A09, 13.2 Integrity).
 * Runs in its own transaction so failed attempts are recorded even when the caller rolls back.
 * Never put secrets or full identifiers in [metadata].
 */
@Service
class AuditService(
    private val jdbc: JdbcTemplate,
    private val objectMapper: ObjectMapper,
) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun record(
        action: AuditAction,
        actorId: UUID? = null,
        deviceId: UUID? = null,
        metadata: Map<String, Any?> = emptyMap(),
    ) {
        jdbc.execute("SELECT pg_advisory_xact_lock($CHAIN_LOCK)")
        val previous = jdbc.query("SELECT row_hash FROM audit_log ORDER BY id DESC LIMIT 1") { rs, _ -> rs.getString(1) }.firstOrNull()
        val occurredAt = Instant.now().truncatedTo(ChronoUnit.MICROS)
        val json = objectMapper.writeValueAsString(metadata)
        val ip = clientIp()
        val traceId = MDC.get(TraceIdFilter.MDC_KEY)
        val rowHash = sha256(listOf(previous, occurredAt, actorId, action, json, ip, deviceId, traceId).joinToString("|"))

        jdbc.update(
            """
            INSERT INTO audit_log (occurred_at, actor_id, action, metadata, ip, device_id, trace_id, previous_hash, row_hash)
            VALUES (?, ?, ?, ?::jsonb, ?::inet, ?, ?, ?, ?)
            """.trimIndent(),
            java.sql.Timestamp.from(occurredAt),
            actorId,
            action.name,
            json,
            ip,
            deviceId,
            traceId,
            previous,
            rowHash,
        )
    }

    private fun clientIp(): String? = (RequestContextHolder.getRequestAttributes() as? ServletRequestAttributes)?.request?.remoteAddr

    private fun sha256(value: String): String = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.toByteArray()))

    private companion object {
        const val CHAIN_LOCK = 4_242_001L
    }
}
