package com.luxebank.integration.stub

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.integration.BillDetails
import com.luxebank.integration.BillPaymentGateway
import com.luxebank.integration.ExternalAccount
import com.luxebank.integration.InterbankTransferGateway
import com.luxebank.integration.PromptPayDirectory
import com.luxebank.integration.StubAdapter
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component
import java.time.Clock
import java.time.LocalDate

/**
 * Deterministic test accounts (spec 7.0): numbers ending in 0000 do not exist,
 * numbers ending in 9999 are rejected by the other bank at transfer time.
 */
object StubDirectory {
    const val NOT_FOUND_SUFFIX = "0000"
    const val REJECTED_SUFFIX = "9999"

    private val names =
        listOf("นาย สมชาย ใจดี", "นางสาว ปรียา รักษ์ไทย", "นาย ธนา มั่งมี", "นาง วิไล ศรีสุข", "บริษัท สยามเทรด จำกัด")

    fun nameFor(key: String): String = names[Math.floorMod(key.hashCode(), names.size)]
}

@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["interbank"], havingValue = "stub", matchIfMissing = true)
class StubInterbankGateway :
    InterbankTransferGateway,
    StubAdapter {
    override fun lookup(
        bankCode: String,
        accountNumber: String,
    ): ExternalAccount? {
        if (accountNumber.endsWith(StubDirectory.NOT_FOUND_SUFFIX)) return null
        return ExternalAccount(bankCode, accountNumber, StubDirectory.nameFor(bankCode + accountNumber))
    }

    override fun transfer(
        to: ExternalAccount,
        amountSatang: Long,
        reference: String,
    ) {
        if (to.accountNumber.endsWith(StubDirectory.REJECTED_SUFFIX)) {
            throw ApiException(ErrorCode.SERVICE_UNAVAILABLE, "The receiving bank is not responding, nothing was deducted")
        }
    }
}

/** Mobile numbers and national IDs resolve to a stub person at a stub bank. */
@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["promptpay"], havingValue = "stub", matchIfMissing = true)
class StubPromptPayDirectory :
    PromptPayDirectory,
    StubAdapter {
    override fun resolve(proxy: String): ExternalAccount? {
        if (proxy.endsWith(StubDirectory.NOT_FOUND_SUFFIX)) return null
        val banks = listOf("KBANK", "SCB", "BBL", "KTB")
        return ExternalAccount(banks[Math.floorMod(proxy.hashCode(), banks.size)], proxy, StubDirectory.nameFor(proxy))
    }
}

/** Each reference owes a stable amount due on the 25th; a reference of all zeros is unknown. */
@Component
@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["bills"], havingValue = "stub", matchIfMissing = true)
class StubBillGateway(
    private val clock: Clock,
) : BillPaymentGateway,
    StubAdapter {
    override fun inquire(
        billerCode: String,
        ref1: String,
        ref2: String?,
    ): BillDetails? {
        if (ref1.all { it == '0' }) return null
        val name = StubDirectory.nameFor(billerCode + ref1)
        if (billerCode in TOP_UPS) return BillDetails(name, null, null)
        val amount = (Math.floorMod((billerCode + ref1).hashCode(), MAX_BAHT - MIN_BAHT) + MIN_BAHT) * SATANG
        val today = LocalDate.now(clock)
        val due = today.withDayOfMonth(DUE_DAY).let { if (it.isBefore(today)) it.plusMonths(1) else it }
        return BillDetails(name, amount.toLong(), due)
    }

    override fun pay(
        billerCode: String,
        ref1: String,
        ref2: String?,
        amountSatang: Long,
        reference: String,
    ) = Unit

    private companion object {
        val TOP_UPS = setOf("AISTOP", "TRUTOP", "TMNW")
        const val MIN_BAHT = 300
        const val MAX_BAHT = 5_000
        const val SATANG = 100
        const val DUE_DAY = 25
    }
}
