package com.luxebank.common.security

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.stereotype.Component
import org.springframework.web.servlet.HandlerInterceptor
import java.time.Duration
import java.time.Instant

/**
 * Fixed-window rate limit per client IP and endpoint for the public auth endpoints
 * (spec 13.1 A07 / API4). Backed by Redis so it holds across instances.
 */
@Component
class AuthRateLimitInterceptor(
    private val redis: StringRedisTemplate,
    private val properties: SecurityProperties,
) : HandlerInterceptor {
    override fun preHandle(
        request: HttpServletRequest,
        response: HttpServletResponse,
        handler: Any,
    ): Boolean {
        val window = Instant.now().epochSecond / WINDOW.seconds
        val key = "rl:${request.requestURI}:${request.remoteAddr}:$window"
        val count = redis.opsForValue().increment(key) ?: 0
        if (count == 1L) redis.expire(key, WINDOW)
        if (count > properties.limits.authRequestsPerMinute) {
            throw ApiException(ErrorCode.RATE_LIMITED, "Too many requests, try again later")
        }
        return true
    }

    private companion object {
        val WINDOW: Duration = Duration.ofMinutes(1)
    }
}
