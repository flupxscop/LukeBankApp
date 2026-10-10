package com.luxebank.common.security

import org.springframework.security.crypto.argon2.Argon2PasswordEncoder
import org.springframework.stereotype.Component
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.HexFormat
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Hashing for secrets (spec 13.1 A02):
 * - PIN and password: Argon2id (OWASP m=19 MiB, t=2, p=1) over HMAC(pepper, secret)
 * - citizen ID: HMAC-SHA256 so it can be looked up without being stored
 * - tokens: SHA-256, they are already high-entropy
 */
@Component
class SecretHasher(
    private val properties: SecurityProperties,
) {
    private val argon2 = Argon2PasswordEncoder(SALT_BYTES, HASH_BYTES, PARALLELISM, MEMORY_KIB, ITERATIONS)
    private val random = SecureRandom()

    /** Used to spend the same time when a user does not exist (timing side channel). */
    private val dummyHash: String by lazy { hashSecret("dummy-secret-for-timing") }

    fun hashSecret(secret: String): String = checkNotNull(argon2.encode(hmacHex(properties.pepper, secret)))

    fun matchesSecret(
        secret: String,
        hash: String,
    ): Boolean = argon2.matches(hmacHex(properties.pepper, secret), hash)

    fun burnTime(secret: String) {
        argon2.matches(hmacHex(properties.pepper, secret), dummyHash)
    }

    fun identityHash(value: String): String = hmacHex(properties.identityKey, value)

    fun tokenHash(token: String): String = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.toByteArray()))

    fun randomToken(bytes: Int = TOKEN_BYTES): String {
        val buffer = ByteArray(bytes)
        random.nextBytes(buffer)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buffer)
    }

    private fun hmacHex(
        key: String,
        value: String,
    ): String {
        val mac = Mac.getInstance(HMAC)
        mac.init(SecretKeySpec(key.toByteArray(), HMAC))
        return HexFormat.of().formatHex(mac.doFinal(value.toByteArray()))
    }

    private companion object {
        const val HMAC = "HmacSHA256"
        const val SALT_BYTES = 16
        const val HASH_BYTES = 32
        const val PARALLELISM = 1
        const val MEMORY_KIB = 19_456
        const val ITERATIONS = 2
        const val TOKEN_BYTES = 32
    }
}
