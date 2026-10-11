package com.luxebank.ledger

import com.luxebank.audit.AuditAction
import com.luxebank.audit.AuditService
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.annotation.EnableScheduling
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component

@Configuration
@EnableScheduling
class SchedulingConfig

/** Daily check that every balance snapshot equals the sum of its postings (spec 13.2 Integrity). */
@Component
class ReconciliationJob(
    private val ledger: LedgerService,
    private val audit: AuditService,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Scheduled(cron = "0 30 2 * * *", zone = "Asia/Bangkok")
    fun reconcile() {
        val mismatched = ledger.unreconciledAccounts()
        if (mismatched.isNotEmpty()) {
            log.error("Ledger reconciliation failed for {} account(s)", mismatched.size)
            audit.record(AuditAction.LEDGER_RECONCILIATION_FAILED, metadata = mapOf("accounts" to mismatched.map { it.toString() }))
        }
    }
}
