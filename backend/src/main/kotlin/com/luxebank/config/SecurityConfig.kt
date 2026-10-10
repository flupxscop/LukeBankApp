package com.luxebank.config

import com.fasterxml.jackson.databind.ObjectMapper
import com.luxebank.common.error.ErrorCode
import com.luxebank.common.error.GlobalExceptionHandler
import jakarta.servlet.http.HttpServletResponse
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter

/**
 * Deny-by-default (spec 13.1, A01). Only health and the API description are public;
 * token authentication for `/api/v1` arrives with M1 (AUTH-07).
 */
@Configuration
class SecurityConfig(
    private val objectMapper: ObjectMapper,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain =
        http
            .csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .httpBasic { it.disable() }
            .formLogin { it.disable() }
            .headers { headers ->
                headers.contentSecurityPolicy { it.policyDirectives("default-src 'none'; frame-ancestors 'none'") }
                headers.referrerPolicy { it.policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.NO_REFERRER) }
                headers.httpStrictTransportSecurity { it.includeSubDomains(true).maxAgeInSeconds(HSTS_SECONDS) }
            }.authorizeHttpRequests {
                it.requestMatchers("/actuator/health", "/actuator/health/**", "/v3/api-docs", "/v3/api-docs/**").permitAll()
                it.anyRequest().denyAll()
            }.exceptionHandling {
                it.authenticationEntryPoint { _, response, _ -> writeError(response, ErrorCode.UNAUTHORIZED, "Authentication required") }
                it.accessDeniedHandler { _, response, _ -> writeError(response, ErrorCode.FORBIDDEN, "Access denied") }
            }.build()

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
    }
}
