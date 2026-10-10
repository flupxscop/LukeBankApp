package com.luxebank.auth

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.common.security.SecurityProperties
import com.luxebank.devices.Device
import com.luxebank.devices.DeviceKeys
import com.luxebank.devices.DeviceRepository
import com.luxebank.users.UserRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.Base64
import java.util.UUID

data class RegistrationStarted(
    val otpRef: String,
    val maskedPhone: String,
    val expiresInSeconds: Long,
)

enum class LoginMethod { PIN, BIOMETRIC }

/**
 * AUTH-01…09. Failure counters are committed even though the request fails
 * (`noRollbackFor`), otherwise lockouts would never trigger.
 */
@Service
@Transactional(noRollbackFor = [ApiException::class])
class AuthService(
    private val users: UserRepository,
    private val devices: DeviceRepository,
    private val otp: OtpService,
    private val challenges: ChallengeService,
    private val tokens: TokenService,
    private val hasher: SecretHasher,
    private val audit: AuditService,
    private val properties: SecurityProperties,
) {
    private val limits get() = properties.limits

    fun startRegistration(
        citizenId: String,
        password: String,
    ): RegistrationStarted {
        val normalized = CitizenId.normalize(citizenId) ?: throw ApiException(ErrorCode.VALIDATION_FAILED, "Citizen ID is invalid")
        val user = users.findByCitizenIdHash(hasher.identityHash(normalized))
        if (user == null) {
            hasher.burnTime(password)
            audit.record(AuditAction.REGISTRATION_FAILED, metadata = mapOf("reason" to "unknown_customer"))
            throw invalidCredentials()
        }
        val now = Instant.now()
        if (user.lockedUntil?.isAfter(now) == true) throw ApiException(ErrorCode.ACCOUNT_LOCKED, "Too many attempts, try again later")

        if (!hasher.matchesSecret(password, user.passwordHash)) {
            user.failedPasswordAttempts += 1
            val remaining = limits.maxPasswordAttempts - user.failedPasswordAttempts
            audit.record(AuditAction.REGISTRATION_FAILED, actorId = user.id, metadata = mapOf("reason" to "wrong_password"))
            if (remaining <= 0) {
                user.failedPasswordAttempts = 0
                user.lockedUntil = now.plus(limits.passwordLockout)
                audit.record(AuditAction.ACCOUNT_LOCKED, actorId = user.id)
                throw ApiException(ErrorCode.ACCOUNT_LOCKED, "Too many attempts, try again later")
            }
            throw invalidCredentials(remaining)
        }

        user.failedPasswordAttempts = 0
        user.lockedUntil = null
        val issued = otp.issue(user.id, user.phone)
        audit.record(AuditAction.REGISTRATION_STARTED, actorId = user.id, metadata = mapOf("otpRef" to issued.reference))
        return RegistrationStarted(issued.reference, user.maskedPhone, issued.expiresInSeconds)
    }

    fun verifyOtp(
        reference: String,
        code: String,
    ): String {
        val userId =
            try {
                otp.verify(reference, code)
            } catch (ex: ApiException) {
                audit.record(AuditAction.OTP_FAILED, metadata = mapOf("otpRef" to reference, "reason" to ex.code.name))
                throw ex
            }
        audit.record(AuditAction.OTP_VERIFIED, actorId = userId)
        return otp.issueRegistrationToken(userId)
    }

    /** Binds this device and revokes any previously bound one (AUTH-09). */
    fun registerDevice(
        registrationToken: String,
        pin: String,
        deviceName: String,
        devicePublicKey: String,
    ): Session {
        if (!PinPolicy.isAcceptable(pin)) throw ApiException(ErrorCode.PIN_POLICY_VIOLATION, "PIN does not meet the rules")
        val publicKey = decodeKey(devicePublicKey)
        val userId = otp.consumeRegistrationToken(registrationToken)

        devices.findByUserIdAndRevokedAtIsNull(userId).forEach { old ->
            old.revokedAt = Instant.now()
            devices.saveAndFlush(old)
            tokens.revokeDevice(old.id)
            audit.record(AuditAction.DEVICE_REVOKED, actorId = userId, deviceId = old.id, metadata = mapOf("reason" to "replaced"))
        }
        val device =
            devices.saveAndFlush(
                Device(userId = userId, deviceName = deviceName, publicKey = publicKey, pinHash = hasher.hashSecret(pin)),
            )
        audit.record(AuditAction.DEVICE_REGISTERED, actorId = userId, deviceId = device.id)
        return tokens.issue(userId, device.id)
    }

    fun challenge(deviceId: UUID): String {
        activeDevice(deviceId)
        return challenges.issue(deviceId)
    }

    fun login(
        deviceId: UUID,
        challenge: String,
        signature: String,
        method: LoginMethod,
        pin: String?,
    ): Session {
        val device = activeDevice(deviceId)
        if (device.pinLocked) throw pinLocked()
        if (!challenges.consume(deviceId, challenge)) throw ApiException(ErrorCode.CHALLENGE_INVALID, "Challenge expired, try again")

        val key =
            when (method) {
                LoginMethod.PIN -> device.publicKey
                LoginMethod.BIOMETRIC ->
                    device.biometricPublicKey ?: throw ApiException(ErrorCode.BIOMETRIC_NOT_ENABLED, "Face ID is not enabled")
            }
        val signatureBytes = decodeBase64(signature, ErrorCode.SIGNATURE_INVALID)
        if (!DeviceKeys.verify(key, challenge.toByteArray(), signatureBytes)) {
            audit.record(AuditAction.LOGIN_FAILED, actorId = device.userId, deviceId = deviceId, metadata = mapOf("reason" to "signature"))
            throw ApiException(ErrorCode.SIGNATURE_INVALID, "Device could not be verified")
        }
        if (method == LoginMethod.PIN) checkPin(device, pin)

        device.failedPinAttempts = 0
        audit.record(AuditAction.LOGIN_SUCCEEDED, actorId = device.userId, deviceId = deviceId, metadata = mapOf("method" to method.name))
        return tokens.issue(device.userId, deviceId)
    }

    fun refresh(refreshToken: String): Session = tokens.rotate(refreshToken)

    fun logout(current: CurrentDevice) {
        val device = activeDevice(current.deviceId)
        device.revokedAt = Instant.now()
        tokens.revokeDevice(device.id)
        audit.record(AuditAction.LOGGED_OUT, actorId = current.userId, deviceId = device.id)
    }

    fun enableBiometric(
        current: CurrentDevice,
        biometricPublicKey: String,
    ) {
        val device = activeDevice(current.deviceId)
        device.biometricPublicKey = decodeKey(biometricPublicKey)
        audit.record(AuditAction.BIOMETRIC_ENABLED, actorId = current.userId, deviceId = device.id)
    }

    fun disableBiometric(current: CurrentDevice) {
        val device = activeDevice(current.deviceId)
        device.biometricPublicKey = null
        audit.record(AuditAction.BIOMETRIC_DISABLED, actorId = current.userId, deviceId = device.id)
    }

    fun changePin(
        current: CurrentDevice,
        currentPin: String,
        newPin: String,
    ) {
        val device = activeDevice(current.deviceId)
        checkPin(device, currentPin)
        if (!PinPolicy.isAcceptable(newPin)) throw ApiException(ErrorCode.PIN_POLICY_VIOLATION, "PIN does not meet the rules")
        device.pinHash = hasher.hashSecret(newPin)
        device.failedPinAttempts = 0
        audit.record(AuditAction.PIN_CHANGED, actorId = current.userId, deviceId = device.id)
    }

    private fun checkPin(
        device: Device,
        pin: String?,
    ) {
        if (pin != null && hasher.matchesSecret(pin, device.pinHash)) return
        device.failedPinAttempts += 1
        val remaining = limits.maxPinAttempts - device.failedPinAttempts
        audit.record(AuditAction.LOGIN_FAILED, actorId = device.userId, deviceId = device.id, metadata = mapOf("reason" to "pin"))
        if (remaining <= 0) {
            device.pinLocked = true
            tokens.revokeDevice(device.id)
            audit.record(AuditAction.PIN_LOCKED, actorId = device.userId, deviceId = device.id)
            throw pinLocked()
        }
        throw ApiException(ErrorCode.PIN_INVALID, "PIN is incorrect", remaining)
    }

    private fun activeDevice(deviceId: UUID): Device =
        devices.findById(deviceId).orElse(null)?.takeIf { it.isActive }
            ?: throw ApiException(ErrorCode.DEVICE_NOT_FOUND, "This device is not registered")

    private fun decodeKey(value: String): ByteArray {
        val bytes = decodeBase64(value, ErrorCode.INVALID_DEVICE_KEY)
        if (!DeviceKeys.isValid(bytes)) throw ApiException(ErrorCode.INVALID_DEVICE_KEY, "Device key is invalid")
        return bytes
    }

    private fun decodeBase64(
        value: String,
        error: ErrorCode,
    ): ByteArray =
        runCatching { Base64.getDecoder().decode(value) }.getOrElse {
            throw ApiException(error, "Value is not valid base64")
        }

    private fun invalidCredentials(remaining: Int? = null) =
        ApiException(ErrorCode.INVALID_CREDENTIALS, "Citizen ID or password is incorrect", remaining)

    private fun pinLocked() = ApiException(ErrorCode.PIN_LOCKED, "PIN locked, verify your identity again")
}
