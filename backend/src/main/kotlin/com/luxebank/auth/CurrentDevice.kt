package com.luxebank.auth

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import org.springframework.core.MethodParameter
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken
import org.springframework.stereotype.Component
import org.springframework.web.bind.support.WebDataBinderFactory
import org.springframework.web.context.request.NativeWebRequest
import org.springframework.web.method.support.HandlerMethodArgumentResolver
import org.springframework.web.method.support.ModelAndViewContainer
import java.util.UUID

/** The signed-in customer and bound device, taken only from the verified access token. */
data class CurrentDevice(
    val userId: UUID,
    val deviceId: UUID,
)

@Component
class CurrentDeviceResolver : HandlerMethodArgumentResolver {
    override fun supportsParameter(parameter: MethodParameter) = parameter.parameterType == CurrentDevice::class.java

    override fun resolveArgument(
        parameter: MethodParameter,
        mavContainer: ModelAndViewContainer?,
        webRequest: NativeWebRequest,
        binderFactory: WebDataBinderFactory?,
    ): CurrentDevice {
        val token =
            SecurityContextHolder.getContext().authentication as? JwtAuthenticationToken
                ?: throw ApiException(ErrorCode.UNAUTHORIZED, "Authentication required")
        val device = token.token.getClaimAsString(TokenService.DEVICE_CLAIM)
        return CurrentDevice(UUID.fromString(token.name), UUID.fromString(device))
    }
}
