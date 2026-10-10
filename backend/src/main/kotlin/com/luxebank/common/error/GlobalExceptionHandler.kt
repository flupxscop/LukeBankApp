package com.luxebank.common.error

import com.luxebank.common.tracing.TraceIdFilter
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.resource.NoResourceFoundException

@RestControllerAdvice
class GlobalExceptionHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(MethodArgumentNotValidException::class, HttpMessageNotReadableException::class)
    fun handleValidation(): ResponseEntity<ApiErrorResponse> = respond(ErrorCode.VALIDATION_FAILED, "Request is invalid")

    @ExceptionHandler(NoResourceFoundException::class)
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
        ) = ApiErrorResponse(ApiError(code.name, message, MDC.get(TraceIdFilter.MDC_KEY)))

        fun respond(
            code: ErrorCode,
            message: String,
        ): ResponseEntity<ApiErrorResponse> = ResponseEntity.status(code.status).body(body(code, message))
    }
}
