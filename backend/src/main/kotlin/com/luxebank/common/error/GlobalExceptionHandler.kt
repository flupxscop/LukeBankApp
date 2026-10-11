package com.luxebank.common.error

import com.luxebank.common.tracing.TraceIdFilter
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.HttpRequestMethodNotSupportedException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.MissingServletRequestParameterException
import org.springframework.web.bind.ServletRequestBindingException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.method.annotation.HandlerMethodValidationException
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException
import org.springframework.web.servlet.resource.NoResourceFoundException

@RestControllerAdvice
class GlobalExceptionHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(ApiException::class)
    fun handleApi(ex: ApiException): ResponseEntity<ApiErrorResponse> = respond(ex.code, ex.message, ex.remainingAttempts)

    @ExceptionHandler(
        MethodArgumentNotValidException::class,
        HandlerMethodValidationException::class,
        HttpMessageNotReadableException::class,
        MethodArgumentTypeMismatchException::class,
        MissingServletRequestParameterException::class,
        ServletRequestBindingException::class,
    )
    fun handleValidation(): ResponseEntity<ApiErrorResponse> = respond(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    @ExceptionHandler(NoResourceFoundException::class, HttpRequestMethodNotSupportedException::class)
    fun handleNotFound(): ResponseEntity<ApiErrorResponse> = respond(ErrorCode.NOT_FOUND, "Resource not found")

    @ExceptionHandler(Exception::class)
    fun handleUnexpected(ex: Exception): ResponseEntity<ApiErrorResponse> {
        log.error("Unhandled error", ex)
        return respond(ErrorCode.INTERNAL_ERROR, "Something went wrong")
    }

    companion object {
        fun body(
            code: ErrorCode,
            message: String,
            remainingAttempts: Int? = null,
        ) = ApiErrorResponse(ApiError(code.name, message, MDC.get(TraceIdFilter.MDC_KEY), remainingAttempts))

        fun respond(
            code: ErrorCode,
            message: String,
            remainingAttempts: Int? = null,
        ): ResponseEntity<ApiErrorResponse> = ResponseEntity.status(code.status).body(body(code, message, remainingAttempts))
    }
}
