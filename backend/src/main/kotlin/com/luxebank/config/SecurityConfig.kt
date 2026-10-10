package com.luxebank.config

import com.luxebank.common.error.ErrorCode
import com.luxebank.common.error.GlobalExceptionHandler
import jakarta.servlet.http.HttpServletResponse
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpMethod
import org.springframework.http.MediaType
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.AuthenticationEntryPoint
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter
import tools.jackson.databind.ObjectMapper

/**
 * Deny-by-default (spec 13.1, A01). Public: health, API description and the unauthenticated
 * auth steps. Everything else under `/api/v1` needs a valid RS256 access token.
 */
@Configuration
class SecurityConfig(
    private val objectMapper: ObjectMapper,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        val entryPoint =
            AuthenticationEntryPoint {
                _,
                response,
                _,
                ->
                writeError(response, ErrorCode.UNAUTHORIZED, "Authentication required")
            }
        return http
            // Bearer tokens only, no cookies: CSRF cannot apply to /api. Keep it on everywhere else.
            .csrf { it.ignoringRequestMatchers("/api/**") }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .httpBasic { it.disable() }
            .formLogin { it.disable() }
            .headers { headers ->
                headers.contentSecurityPolicy { it.policyDirectives("default-src 'none'; frame-ancestors 'none'") }
                headers.referrerPolicy { it.policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.NO_REFERRER) }
                headers.httpStrictTransportSecurity { it.includeSubDomains(true).maxAgeInSeconds(HSTS_SECONDS) }
            }.authorizeHttpRequests {
                it.requestMatchers("/actuator/health", "/actuator/health/**", "/v3/api-docs", "/v3/api-docs/**").permitAll()
                it.requestMatchers(HttpMethod.POST, *PUBLIC_AUTH).permitAll()
                it.requestMatchers("/api/v1/**").authenticated()
                it.anyRequest().denyAll()
            }.oauth2ResourceServer {
                it.jwt { }
                it.authenticationEntryPoint(entryPoint)
            }.exceptionHandling {
                it.authenticationEntryPoint(entryPoint)
                it.accessDeniedHandler { _, response, _ -> writeError(response, ErrorCode.FORBIDDEN, "Access denied") }
            }.build()
    }

    private fun writeError(
        response: HttpServletResponse,
        code: ErrorCode,
        message: String,
    ) {
        response.status = code.status.value()
        response.contentType = MediaType.APPLICATION_JSON_VALUE
        objectMapper.writeValue(response.outputStream, GlobalExceptionHandler.body(code, message))
    }

    private companion object {
        const val HSTS_SECONDS = 31_536_000L
        val PUBLIC_AUTH =
            arrayOf(
                "/api/v1/auth/register",
                "/api/v1/auth/otp/verify",
                "/api/v1/auth/devices",
                "/api/v1/auth/challenge",
                "/api/v1/auth/login",
                "/api/v1/auth/refresh",
            )
    }
}
