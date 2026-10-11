package com.luxebank.common.error

import com.fasterxml.jackson.annotation.JsonInclude
import org.springframework.http.HttpStatus

/**
 * Error body shared by every endpoint (spec section 9). Never carries stack traces
 * or internal details (spec 13.1, A05).
 */
data class ApiErrorResponse(
    val error: ApiError,
)

@JsonInclude(JsonInclude.Include.NON_NULL)
data class ApiError(
    val code: String,
    val message: String,
    val traceId: String?,
    val remainingAttempts: Int? = null,
)

enum class ErrorCode(
    val status: HttpStatus,
) {
    VALIDATION_FAILED(HttpStatus.BAD_REQUEST),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED),
    FORBIDDEN(HttpStatus.FORBIDDEN),
    NOT_FOUND(HttpStatus.NOT_FOUND),
    RATE_LIMITED(HttpStatus.TOO_MANY_REQUESTS),
    SERVICE_UNAVAILABLE(HttpStatus.SERVICE_UNAVAILABLE),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR),

    // Authentication (AUTH-*)
    INVALID_CREDENTIALS(HttpStatus.UNAUTHORIZED),
    ACCOUNT_LOCKED(HttpStatus.LOCKED),
    OTP_INVALID(HttpStatus.UNAUTHORIZED),
    OTP_EXPIRED(HttpStatus.GONE),
    OTP_LOCKED(HttpStatus.LOCKED),
    REGISTRATION_EXPIRED(HttpStatus.GONE),
    PIN_POLICY_VIOLATION(HttpStatus.BAD_REQUEST),
    PIN_INVALID(HttpStatus.UNAUTHORIZED),
    PIN_LOCKED(HttpStatus.LOCKED),
    INVALID_DEVICE_KEY(HttpStatus.BAD_REQUEST),
    DEVICE_NOT_FOUND(HttpStatus.NOT_FOUND),
    CHALLENGE_INVALID(HttpStatus.UNAUTHORIZED),
    SIGNATURE_INVALID(HttpStatus.UNAUTHORIZED),
    BIOMETRIC_NOT_ENABLED(HttpStatus.CONFLICT),
    TOKEN_INVALID(HttpStatus.UNAUTHORIZED),
    DEVICE_COMPROMISED(HttpStatus.FORBIDDEN),

    // Money (TRF-*, ledger)
    INSUFFICIENT_FUNDS(HttpStatus.UNPROCESSABLE_CONTENT),
    ACCOUNT_UNAVAILABLE(HttpStatus.CONFLICT),
    DAILY_LIMIT_EXCEEDED(HttpStatus.UNPROCESSABLE_CONTENT),
    STEP_UP_REQUIRED(HttpStatus.FORBIDDEN),
    RECIPIENT_NOT_FOUND(HttpStatus.NOT_FOUND),
    BILL_NOT_FOUND(HttpStatus.NOT_FOUND),
    INQUIRY_EXPIRED(HttpStatus.GONE),
    DUPLICATE_REQUEST(HttpStatus.CONFLICT),
    QR_INVALID(HttpStatus.BAD_REQUEST),
}

/** Business error that maps to the shared error body. */
class ApiException(
    val code: ErrorCode,
    override val message: String,
    val remainingAttempts: Int? = null,
) : RuntimeException(message)
