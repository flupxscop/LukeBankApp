package com.luxebank.integration.stub

import com.luxebank.integration.PushNotifier
import com.luxebank.integration.StubAdapter
import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component

/** Logs instead of calling APNs; the in-app inbox still receives every notification. Never logs content. */
@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["push"], havingValue = "stub", matchIfMissing = true)
class StubPushNotifier :
    PushNotifier,
    StubAdapter {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun send(
        pushToken: String,
        title: String,
        body: String,
        category: String,
    ) {
        log.info("Stub push ({}) to …{}", category, pushToken.takeLast(TOKEN_VISIBLE))
    }

    private companion object {
        const val TOKEN_VISIBLE = 6
    }
}
