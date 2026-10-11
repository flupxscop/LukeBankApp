package com.luxebank.common.security

import org.springframework.boot.context.properties.ConfigurationProperties
import java.time.Duration

@ConfigurationProperties("luxebank.security")
data class SecurityProperties(
    /** Mixed into every PIN and password before hashing; lives in KMS in production. */
    val pepper: String,
    /** Key for the searchable HMAC of citizen IDs (spec 13.3.1). */
    val identityKey: String,
    val jwt: Jwt = Jwt(),
    val limits: Limits = Limits(),
) {
    data class Jwt(
        val issuer: String = "https://api.luxebank.local",
        val accessTokenTtl: Duration = Duration.ofMinutes(15),
        val refreshTokenTtl: Duration = Duration.ofDays(30),
        /** PKCS#8 PEM. Required in production; generated per start elsewhere. */
        val privateKey: String? = null,
        /** X.509 PEM matching [privateKey]. */
        val publicKey: String? = null,
    )

    data class Limits(
        val maxPasswordAttempts: Int = 5,
        val passwordLockout: Duration = Duration.ofMinutes(15),
        val maxOtpAttempts: Int = 5,
        val otpTtl: Duration = Duration.ofMinutes(5),
        val registrationTokenTtl: Duration = Duration.ofMinutes(10),
        val maxPinAttempts: Int = 5,
        val challengeTtl: Duration = Duration.ofMinutes(2),
        val authRequestsPerMinute: Int = 20,
        /** Name inquiries per customer per minute; slows down recipient enumeration (API6). */
        val paymentInquiriesPerMinute: Int = 30,
    )
}
