package com.luxebank.payments

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.auth.CurrentDevice
import com.luxebank.auth.LoginMethod
import com.luxebank.auth.TokenService
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.common.security.SecurityProperties
import com.luxebank.devices.Device
import com.luxebank.devices.DeviceKeys
import com.luxebank.devices.DeviceRepository
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import java.util.Base64

/**
 * Proves the payment comes from the bound device and its owner (TRF-07, TRF-09, 13.1 A08):
 * the device key signs the inquiry's single-use challenge, plus the PIN or a Face ID-gated key.
 *
 * Runs in its own transaction so wrong-PIN counts and lockouts are kept even though the
 * payment itself rolls back.
 */
@Component
class PaymentAuthorizer(
    private val devices: DeviceRepository,
    private val hasher: SecretHasher,
    private val tokens: TokenService,
    private val audit: AuditService,
    private val properties: SecurityProperties,
) {
    @Transactional(propagation = Propagation.REQUIRES_NEW, noRollbackFor = [ApiException::class])
    fun authorize(
        current: CurrentDevice,
        challenge: String,
        proof: PaymentProof,
        requiresBiometric: Boolean,
    ) {
        val device =
            devices.findById(current.deviceId).orElse(null)?.takeIf { it.isActive && it.userId == current.userId }
                ?: throw ApiException(ErrorCode.DEVICE_NOT_FOUND, "This device is not registered")
        if (device.pinLocked) throw ApiException(ErrorCode.PIN_LOCKED, "PIN locked, verify your identity again")
        if (requiresBiometric && proof.method != LoginMethod.BIOMETRIC) {
            throw ApiException(ErrorCode.STEP_UP_REQUIRED, "Confirm this with Face ID")
        }

        verifySignature(current, device, challenge, proof)
        if (proof.method == LoginMethod.PIN) checkPin(current, device, proof.pin)
        device.failedPinAttempts = 0
    }

    private fun verifySignature(
        current: CurrentDevice,
        device: Device,
        challenge: String,
        proof: PaymentProof,
    ) {
        val key =
            when (proof.method) {
                LoginMethod.PIN -> device.publicKey
                LoginMethod.BIOMETRIC ->
                    device.biometricPublicKey ?: throw ApiException(ErrorCode.BIOMETRIC_NOT_ENABLED, "Face ID is not enabled")
            }
        val signature = runCatching { Base64.getDecoder().decode(proof.signature) }.getOrNull()
        if (signature == null || !DeviceKeys.verify(key, challenge.toByteArray(), signature)) {
            audit.record(AuditAction.PAYMENT_AUTH_FAILED, current.userId, current.deviceId, mapOf("reason" to "signature"))
            throw ApiException(ErrorCode.SIGNATURE_INVALID, "Device could not be verified")
        }
    }

    private fun checkPin(
        current: CurrentDevice,
        device: Device,
        pin: String?,
    ) {
        if (pin != null && hasher.matchesSecret(pin, device.pinHash)) return
        device.failedPinAttempts += 1
        val remaining = properties.limits.maxPinAttempts - device.failedPinAttempts
        audit.record(AuditAction.PAYMENT_AUTH_FAILED, current.userId, current.deviceId, mapOf("reason" to "pin"))
        if (remaining <= 0) {
            device.pinLocked = true
            tokens.revokeDevice(device.id)
            audit.record(AuditAction.PIN_LOCKED, actorId = device.userId, deviceId = device.id)
            throw ApiException(ErrorCode.PIN_LOCKED, "PIN locked, verify your identity again")
        }
        throw ApiException(ErrorCode.PIN_INVALID, "PIN is incorrect", remaining)
    }
}

data class PaymentProof(
    val method: LoginMethod,
    val signature: String,
    val pin: String? = null,
)
