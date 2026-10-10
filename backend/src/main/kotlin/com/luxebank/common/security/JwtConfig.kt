package com.luxebank.common.security

import com.nimbusds.jose.jwk.JWKSet
import com.nimbusds.jose.jwk.RSAKey
import com.nimbusds.jose.jwk.source.ImmutableJWKSet
import com.nimbusds.jose.proc.SecurityContext
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.env.Environment
import org.springframework.core.env.Profiles
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator
import org.springframework.security.oauth2.jwt.JwtDecoder
import org.springframework.security.oauth2.jwt.JwtEncoder
import org.springframework.security.oauth2.jwt.JwtValidators
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPrivateKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** RS256 access tokens (spec 13.1 A02). Keys come from KMS-provided PEM in production. */
@Configuration
class JwtConfig(
    private val properties: SecurityProperties,
    private val environment: Environment,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    fun signingKey(): RSAKey {
        val jwt = properties.jwt
        if (jwt.privateKey != null && jwt.publicKey != null) {
            val factory = KeyFactory.getInstance("RSA")
            val privateKey = factory.generatePrivate(PKCS8EncodedKeySpec(pem(jwt.privateKey))) as RSAPrivateKey
            val publicKey = factory.generatePublic(X509EncodedKeySpec(pem(jwt.publicKey))) as RSAPublicKey
            return RSAKey
                .Builder(publicKey)
                .privateKey(privateKey)
                .keyID("luxebank-access")
                .build()
        }
        check(!environment.acceptsProfiles(Profiles.of("prod"))) { "JWT signing keys must be configured in production" }
        log.warn("No JWT keys configured; generating an ephemeral key pair (tokens reset on restart)")
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(RSA_BITS) }.generateKeyPair()
        return RSAKey
            .Builder(pair.public as RSAPublicKey)
            .privateKey(pair.private as RSAPrivateKey)
            .keyID("luxebank-ephemeral")
            .build()
    }

    @Bean
    fun jwtEncoder(signingKey: RSAKey): JwtEncoder = NimbusJwtEncoder(ImmutableJWKSet<SecurityContext>(JWKSet(signingKey)))

    @Bean
    fun jwtDecoder(signingKey: RSAKey): JwtDecoder =
        NimbusJwtDecoder.withPublicKey(signingKey.toRSAPublicKey()).build().apply {
            setJwtValidator(DelegatingOAuth2TokenValidator(JwtValidators.createDefaultWithIssuer(properties.jwt.issuer)))
        }

    private fun pem(value: String): ByteArray =
        Base64.getDecoder().decode(
            value
                .lines()
                .filterNot { it.startsWith("-----") }
                .joinToString("")
                .trim(),
        )

    private companion object {
        const val RSA_BITS = 2048
    }
}
