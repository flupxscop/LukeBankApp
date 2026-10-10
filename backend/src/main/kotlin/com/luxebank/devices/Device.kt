package com.luxebank.devices

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import jakarta.persistence.Version
import org.springframework.data.jpa.repository.JpaRepository
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "devices")
class Device(
    @Id
    val id: UUID = UUID.randomUUID(),
    @Column(name = "user_id", nullable = false)
    val userId: UUID,
    @Column(name = "device_name", nullable = false)
    val deviceName: String,
    @Column(name = "public_key", nullable = false)
    val publicKey: ByteArray,
    @Column(name = "biometric_public_key")
    var biometricPublicKey: ByteArray? = null,
    @Column(name = "pin_hash", nullable = false)
    var pinHash: String,
    @Column(name = "failed_pin_attempts", nullable = false)
    var failedPinAttempts: Int = 0,
    @Column(name = "pin_locked", nullable = false)
    var pinLocked: Boolean = false,
    @Column(name = "registered_at", nullable = false)
    val registeredAt: Instant = Instant.now(),
    @Column(name = "revoked_at")
    var revokedAt: Instant? = null,
    @Version
    var version: Long = 0,
) {
    val isActive: Boolean get() = revokedAt == null
}

interface DeviceRepository : JpaRepository<Device, UUID> {
    fun findByUserIdAndRevokedAtIsNull(userId: UUID): List<Device>
}
