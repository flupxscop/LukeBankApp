package com.luxebank.auth

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.common.security.SecurityProperties
import com.luxebank.devices.DeviceRepository
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.LockModeType
import jakarta.persistence.Table
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Lock
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm
import org.springframework.security.oauth2.jwt.JwsHeader
import org.springframework.security.oauth2.jwt.JwtClaimsSet
import org.springframework.security.oauth2.jwt.JwtEncoder
import org.springframework.security.oauth2.jwt.JwtEncoderParameters
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "refresh_tokens")
class RefreshToken(
    @Id
    val id: UUID = UUID.randomUUID(),
    @Column(name = "family_id", nullable = false)
    val familyId: UUID,
    @Column(name = "device_id", nullable = false)
    val deviceId: UUID,
    @Column(name = "token_hash", nullable = false, unique = true)
    val tokenHash: String,
    @Column(name = "expires_at", nullable = false)
    val expiresAt: Instant,
    @Column(name = "used_at")
    var usedAt: Instant? = null,
    @Column(name = "revoked_at")
    var revokedAt: Instant? = null,
    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),
)

interface RefreshTokenRepository : JpaRepository<RefreshToken, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    fun findByTokenHash(tokenHash: String): RefreshToken?

    @Modifying
    @Query("UPDATE RefreshToken t SET t.revokedAt = :now WHERE t.familyId = :familyId AND t.revokedAt IS NULL")
    fun revokeFamily(
        familyId: UUID,
        now: Instant,
    ): Int

    @Modifying
    @Query("UPDATE RefreshToken t SET t.revokedAt = :now WHERE t.deviceId = :deviceId AND t.revokedAt IS NULL")
    fun revokeDevice(
        deviceId: UUID,
        now: Instant,
    ): Int
}

data class Session(
    val deviceId: UUID,
    val accessToken: String,
    val refreshToken: String,
    val expiresInSeconds: Long,
)

/** Short-lived RS256 access tokens plus rotating refresh tokens with reuse detection (AUTH-07). */
@Service
class TokenService(
    private val encoder: JwtEncoder,
    private val refreshTokens: RefreshTokenRepository,
    private val devices: DeviceRepository,
    private val hasher: SecretHasher,
    private val audit: AuditService,
    private val properties: SecurityProperties,
) {
    @Transactional
    fun issue(
        userId: UUID,
        deviceId: UUID,
        familyId: UUID = UUID.randomUUID(),
    ): Session {
        val now = Instant.now()
        val jwt = properties.jwt
        val claims =
            JwtClaimsSet
                .builder()
                .issuer(jwt.issuer)
                .subject(userId.toString())
                .claim(DEVICE_CLAIM, deviceId.toString())
                .issuedAt(now)
                .expiresAt(now.plus(jwt.accessTokenTtl))
                .id(UUID.randomUUID().toString())
                .build()
        val header = JwsHeader.with(SignatureAlgorithm.RS256).build()
        val accessToken = encoder.encode(JwtEncoderParameters.from(header, claims)).tokenValue

        val refreshToken = hasher.randomToken()
        refreshTokens.save(
            RefreshToken(
                familyId = familyId,
                deviceId = deviceId,
                tokenHash = hasher.tokenHash(refreshToken),
                expiresAt = now.plus(jwt.refreshTokenTtl),
            ),
        )
        return Session(deviceId, accessToken, refreshToken, jwt.accessTokenTtl.seconds)
    }

    @Transactional(noRollbackFor = [ApiException::class])
    fun rotate(refreshToken: String): Session {
        val now = Instant.now()
        val stored = refreshTokens.findByTokenHash(hasher.tokenHash(refreshToken)) ?: throw invalid()
        if (stored.usedAt != null || stored.revokedAt != null) {
            refreshTokens.revokeFamily(stored.familyId, now)
            audit.record(AuditAction.TOKEN_REUSE_DETECTED, deviceId = stored.deviceId)
            throw invalid()
        }
        val device = devices.findById(stored.deviceId).orElse(null)
        if (stored.expiresAt.isBefore(now) || device == null || !device.isActive || device.pinLocked) throw invalid()
        stored.usedAt = now
        return issue(device.userId, device.id, stored.familyId)
    }

    @Transactional
    fun revokeDevice(deviceId: UUID) {
        refreshTokens.revokeDevice(deviceId, Instant.now())
    }

    private fun invalid() = ApiException(ErrorCode.TOKEN_INVALID, "Session expired, sign in again")

    companion object {
        const val DEVICE_CLAIM = "did"
    }
}
