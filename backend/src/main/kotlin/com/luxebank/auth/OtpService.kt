package com.luxebank.auth

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.security.SecretHasher
import com.luxebank.common.security.SecurityProperties
import com.luxebank.integration.OtpCodeGenerator
import com.luxebank.integration.OtpSender
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.stereotype.Service
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

data class IssuedOtp(
    val reference: String,
    val expiresInSeconds: Long,
)

/** One-time codes and short-lived registration tokens, kept in Redis (AUTH-01, AUTH-05). */
@Service
class OtpService(
    private val redis: StringRedisTemplate,
    private val sender: OtpSender,
    private val generator: OtpCodeGenerator,
    private val hasher: SecretHasher,
    private val properties: SecurityProperties,
) {
    private val random = SecureRandom()

    fun issue(
        userId: UUID,
        phone: String,
    ): IssuedOtp {
        val code = generator.generate()
        val ttl = properties.limits.otpTtl
        var reference: String
        do {
            reference = randomReference()
        } while (redis.opsForHash<String, String>().hasKey(otpKey(reference), USER_ID))
        redis.opsForHash<String, String>().putAll(
            otpKey(reference),
            mapOf(USER_ID to userId.toString(), CODE_HASH to hasher.tokenHash(code), ATTEMPTS to "0"),
        )
        redis.expire(otpKey(reference), ttl)
        sender.send(phone, code, reference)
        return IssuedOtp(reference, ttl.seconds)
    }

    /** Returns the user ID when the code matches; counts and locks wrong attempts. */
    fun verify(
        reference: String,
        code: String,
    ): UUID {
        val key = otpKey(reference)
        val entry = redis.opsForHash<String, String>().entries(key)
        val userId = entry[USER_ID] ?: throw ApiException(ErrorCode.OTP_EXPIRED, "Code expired, request a new one")
        val expected = entry[CODE_HASH].orEmpty().toByteArray()
        if (MessageDigest.isEqual(expected, hasher.tokenHash(code).toByteArray())) {
            redis.delete(key)
            return UUID.fromString(userId)
        }
        val attempts = redis.opsForHash<String, String>().increment(key, ATTEMPTS, 1)
        val remaining = properties.limits.maxOtpAttempts - attempts.toInt()
        if (remaining <= 0) {
            redis.delete(key)
            throw ApiException(ErrorCode.OTP_LOCKED, "Too many wrong codes, start again")
        }
        throw ApiException(ErrorCode.OTP_INVALID, "Code is incorrect", remaining)
    }

    fun issueRegistrationToken(userId: UUID): String {
        val token = hasher.randomToken()
        redis.opsForValue().set(registrationKey(token), userId.toString(), properties.limits.registrationTokenTtl)
        return token
    }

    fun consumeRegistrationToken(token: String): UUID {
        val userId =
            redis.opsForValue().getAndDelete(registrationKey(token))
                ?: throw ApiException(ErrorCode.REGISTRATION_EXPIRED, "Registration expired, start again")
        return UUID.fromString(userId)
    }

    private fun otpKey(reference: String) = "otp:$reference"

    private fun registrationKey(token: String) = "reg:${hasher.tokenHash(token)}"

    private fun randomReference(): String = (1..REFERENCE_LENGTH).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")

    private companion object {
        const val USER_ID = "userId"
        const val CODE_HASH = "codeHash"
        const val ATTEMPTS = "attempts"
        const val REFERENCE_LENGTH = 4
        const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    }
}
