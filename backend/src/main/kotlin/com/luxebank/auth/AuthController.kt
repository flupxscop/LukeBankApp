package com.luxebank.auth

import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.util.UUID

private const val PIN_PATTERN = "^\\d{6}$"
private const val BASE64_PATTERN = "^[A-Za-z0-9+/=_-]+$"
private const val MAX_KEY = 200
private const val MAX_TOKEN = 100
private const val MAX_SIGNATURE = 200

data class RegisterRequest(
    @field:NotBlank @field:Size(max = 20) val citizenId: String,
    @field:NotBlank @field:Size(max = 128) val password: String,
)

data class OtpVerifyRequest(
    @field:Pattern(regexp = "^[A-Z0-9]{4}$") val otpRef: String,
    @field:Pattern(regexp = PIN_PATTERN) val code: String,
)

data class RegistrationTokenResponse(
    val registrationToken: String,
)

data class DeviceRegistrationRequest(
    @field:NotBlank @field:Size(max = MAX_TOKEN) val registrationToken: String,
    @field:Pattern(regexp = PIN_PATTERN) val pin: String,
    @field:NotBlank @field:Size(max = 100) val deviceName: String,
    @field:Size(max = MAX_KEY) @field:Pattern(regexp = BASE64_PATTERN) val devicePublicKey: String,
)

data class ChallengeRequest(
    val deviceId: UUID,
)

data class ChallengeResponse(
    val challenge: String,
    val expiresInSeconds: Long,
)

data class LoginRequest(
    val deviceId: UUID,
    @field:NotBlank @field:Size(max = MAX_TOKEN) val challenge: String,
    @field:Size(max = MAX_SIGNATURE) @field:Pattern(regexp = BASE64_PATTERN) val signature: String,
    val method: LoginMethod,
    @field:Pattern(regexp = PIN_PATTERN) val pin: String? = null,
)

data class RefreshRequest(
    @field:NotBlank @field:Size(max = MAX_TOKEN) val refreshToken: String,
)

data class BiometricRequest(
    @field:Size(max = MAX_KEY) @field:Pattern(regexp = BASE64_PATTERN) val biometricPublicKey: String,
)

data class ChangePinRequest(
    @field:Pattern(regexp = PIN_PATTERN) val currentPin: String,
    @field:Pattern(regexp = PIN_PATTERN) val newPin: String,
)

@RestController
@RequestMapping("/api/v1/auth")
class AuthController(
    private val auth: AuthService,
    private val challenges: ChallengeService,
) {
    @PostMapping("/register")
    fun register(
        @Valid @RequestBody body: RegisterRequest,
    ) = auth.startRegistration(body.citizenId, body.password)

    @PostMapping("/otp/verify")
    fun verifyOtp(
        @Valid @RequestBody body: OtpVerifyRequest,
    ) = RegistrationTokenResponse(auth.verifyOtp(body.otpRef, body.code))

    @PostMapping("/devices")
    fun registerDevice(
        @Valid @RequestBody body: DeviceRegistrationRequest,
    ) = auth.registerDevice(body.registrationToken, body.pin, body.deviceName, body.devicePublicKey)

    @PostMapping("/challenge")
    fun challenge(
        @Valid @RequestBody body: ChallengeRequest,
    ) = ChallengeResponse(auth.challenge(body.deviceId), challenges.ttlSeconds)

    @PostMapping("/login")
    fun login(
        @Valid @RequestBody body: LoginRequest,
    ) = auth.login(body.deviceId, body.challenge, body.signature, body.method, body.pin)

    @PostMapping("/refresh")
    fun refresh(
        @Valid @RequestBody body: RefreshRequest,
    ) = auth.refresh(body.refreshToken)

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun logout(current: CurrentDevice) = auth.logout(current)

    @PutMapping("/biometric")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun enableBiometric(
        current: CurrentDevice,
        @Valid @RequestBody body: BiometricRequest,
    ) = auth.enableBiometric(current, body.biometricPublicKey)

    @DeleteMapping("/biometric")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun disableBiometric(current: CurrentDevice) = auth.disableBiometric(current)

    @PutMapping("/pin")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun changePin(
        current: CurrentDevice,
        @Valid @RequestBody body: ChangePinRequest,
    ) = auth.changePin(current, body.currentPin, body.newPin)
}
