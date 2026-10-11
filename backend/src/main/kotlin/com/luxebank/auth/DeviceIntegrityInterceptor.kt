package com.luxebank.auth

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken
import org.springframework.stereotype.Component
import org.springframework.web.servlet.HandlerInterceptor
import java.util.UUID

/**
 * AUTH-11: the app reports a jailbroken phone or an attached debugger with `X-Device-Integrity: compromised`;
 * moving money and revealing card details are then refused. An attacker can hide the signal, so its absence
 * proves nothing; it only protects customers on a compromised phone who did not do it themselves.
 * Viewing, blocking a lost card and signing out stay available.
 */
@Component
class DeviceIntegrityInterceptor(
    private val audit: AuditService,
) : HandlerInterceptor {
    override fun preHandle(
        request: HttpServletRequest,
        response: HttpServletResponse,
        handler: Any,
    ): Boolean {
        if (request.getHeader(HEADER)?.equals(COMPROMISED, ignoreCase = true) != true) return true
        val token = SecurityContextHolder.getContext().authentication as? JwtAuthenticationToken
        audit.record(
            AuditAction.DEVICE_INTEGRITY_BLOCKED,
            actorId = token?.name?.let(UUID::fromString),
            deviceId = token?.token?.getClaimAsString(TokenService.DEVICE_CLAIM)?.let(UUID::fromString),
            metadata = mapOf("path" to request.requestURI),
        )
        throw ApiException(ErrorCode.DEVICE_COMPROMISED, "Not available on this device")
    }

    companion object {
        const val HEADER = "X-Device-Integrity"
        const val COMPROMISED = "compromised"

        /** Endpoints that move money or reveal card details. */
        val PROTECTED = listOf("/api/v1/transfers", "/api/v1/bills/payments", "/api/v1/cards/*/sensitive")
    }
}
