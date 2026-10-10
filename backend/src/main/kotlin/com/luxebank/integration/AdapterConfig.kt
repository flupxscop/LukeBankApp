package com.luxebank.integration

import org.springframework.beans.factory.SmartInitializingSingleton
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean
import org.springframework.context.ApplicationContext
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import java.security.SecureRandom

@Configuration
class AdapterConfig {
    @Bean
    @ConditionalOnMissingBean(OtpCodeGenerator::class)
    fun secureOtpCodeGenerator(): OtpCodeGenerator {
        val random = SecureRandom()
        return OtpCodeGenerator { "%06d".format(random.nextInt(OTP_SPACE)) }
    }

    private companion object {
        const val OTP_SPACE = 1_000_000
    }
}

/** Refuses to start production while any stub adapter is still wired in (spec 7.0). */
@Component
@Profile("prod")
class ProductionAdapterGuard(
    private val context: ApplicationContext,
) : SmartInitializingSingleton {
    override fun afterSingletonsInstantiated() {
        val stubs = context.getBeansOfType(StubAdapter::class.java).keys
        check(stubs.isEmpty()) { "Stub adapters are not allowed in production: $stubs" }
    }
}
