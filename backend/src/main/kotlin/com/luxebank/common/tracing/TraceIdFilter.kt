package com.luxebank.common.tracing

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.slf4j.MDC
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.util.UUID

/**
 * Propagates `X-Trace-Id` from the app (spec section 9, NFR-13) into logs and responses.
 * Accepts only a safe token shape to avoid log injection.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class TraceIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val incoming = request.getHeader(HEADER)
        val traceId = if (incoming != null && SAFE_TRACE_ID.matches(incoming)) incoming else UUID.randomUUID().toString()
        MDC.put(MDC_KEY, traceId)
        response.setHeader(HEADER, traceId)
        try {
            filterChain.doFilter(request, response)
        } finally {
            MDC.remove(MDC_KEY)
        }
    }

    companion object {
        const val HEADER = "X-Trace-Id"
        const val MDC_KEY = "traceId"
        private val SAFE_TRACE_ID = Regex("^[A-Za-z0-9-]{8,64}$")
    }
}
