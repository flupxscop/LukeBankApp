package com.luxebank.auth

import com.luxebank.common.security.SecretHasher
import com.luxebank.common.security.SecurityProperties
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.stereotype.Service
import java.util.UUID

/**
 * Single-use login challenges. The device signs the challenge with its Secure Enclave key,
 * proving possession of the bound device (spec 13.1 A07/A08).
 */
@Service
class ChallengeService(
    private val redis: StringRedisTemplate,
    private val hasher: SecretHasher,
    private val properties: SecurityProperties,
) {
    fun issue(deviceId: UUID): String {
        val challenge = hasher.randomToken()
        redis.opsForValue().set(key(deviceId, challenge), "1", properties.limits.challengeTtl)
        return challenge
    }

    fun consume(
        deviceId: UUID,
        challenge: String,
    ): Boolean = redis.delete(key(deviceId, challenge))

    val ttlSeconds: Long get() = properties.limits.challengeTtl.seconds

    private fun key(
        deviceId: UUID,
        challenge: String,
    ) = "chal:$deviceId:${hasher.tokenHash(challenge)}"
}
