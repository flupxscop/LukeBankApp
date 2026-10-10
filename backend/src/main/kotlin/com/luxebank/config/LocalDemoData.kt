package com.luxebank.config

import com.luxebank.common.security.SecretHasher
import com.luxebank.users.User
import com.luxebank.users.UserRepository
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

/**
 * Demo customer for local development only. Values are synthetic (spec 13.3.2):
 * citizen ID 1-2345-67890-12-1, password LuxeDemo#2026, OTP 000000.
 */
@Component
@Profile("local")
class LocalDemoData(
    private val users: UserRepository,
    private val hasher: SecretHasher,
) : ApplicationRunner {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val citizenHash = hasher.identityHash(DEMO_CITIZEN_ID)
        if (users.findByCitizenIdHash(citizenHash) != null) return
        users.save(
            User(
                citizenIdHash = citizenHash,
                passwordHash = hasher.hashSecret(DEMO_PASSWORD),
                phone = "0812344521",
                firstNameTh = "นกน้อย",
                firstNameEn = "Noknoi",
                tier = "GOLD",
            ),
        )
        log.info("Created local demo customer")
    }

    private companion object {
        const val DEMO_CITIZEN_ID = "1234567890121"
        const val DEMO_PASSWORD = "LuxeDemo#2026"
    }
}
