package com.luxebank.config

import com.luxebank.auth.CurrentDeviceResolver
import com.luxebank.common.security.AuthRateLimitInterceptor
import org.springframework.context.annotation.Configuration
import org.springframework.web.method.support.HandlerMethodArgumentResolver
import org.springframework.web.servlet.config.annotation.InterceptorRegistry
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer

@Configuration
class WebConfig(
    private val rateLimit: AuthRateLimitInterceptor,
    private val currentDevice: CurrentDeviceResolver,
) : WebMvcConfigurer {
    override fun addInterceptors(registry: InterceptorRegistry) {
        registry.addInterceptor(rateLimit).addPathPatterns("/api/v1/auth/**")
    }

    override fun addArgumentResolvers(resolvers: MutableList<HandlerMethodArgumentResolver>) {
        resolvers.add(currentDevice)
    }
}
