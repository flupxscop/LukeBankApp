package com.luxebank.common.error

import org.springframework.http.HttpStatus

/**
 * Error body shared by every endpoint (spec section 9). Never carries stack traces
 * or internal details (spec 13.1, A05).
 */
data class ApiErrorResponse(
    val error: ApiError,
)

data class ApiError(
    val code: String,
    val message: String,
    val traceId: String?,
)

enum class ErrorCode(
    val status: HttpStatus,
) {
    VALIDATION_FAILED(HttpStatus.BAD_REQUEST),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED),
    FORBIDDEN(HttpStatus.FORBIDDEN),
    NOT_FOUND(HttpStatus.NOT_FOUND),
    SERVICE_UNAVAILABLE(HttpStatus.SERVICE_UNAVAILABLE),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR),
}
