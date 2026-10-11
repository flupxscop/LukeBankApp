package com.luxebank.ledger

import java.time.Clock
import java.time.ZoneId

/** Business days and months follow Thai time (spec 6.5). */
object BankTime {
    val ZONE: ZoneId = ZoneId.of("Asia/Bangkok")

    fun clock(): Clock = Clock.system(ZONE)
}

/** Amounts are integer satang inside the system and decimal strings ("-580.00") on the API (spec 6.5). */
object Money {
    private const val SATANG_PER_BAHT = 100L
    private const val FRACTION_DIGITS = 2

    fun format(satang: Long): String {
        val sign = if (satang < 0) "-" else ""
        val abs = Math.absExact(satang)
        val fraction = (abs % SATANG_PER_BAHT).toString().padStart(FRACTION_DIGITS, '0')
        return "$sign${abs / SATANG_PER_BAHT}.$fraction"
    }
}

enum class SpendingKind {
    LIFESTYLE,
    TRAVEL,
    ;

    val code: String get() = name.lowercase()
}

/** Transaction category; `kind` groups spending categories for budgets (DASH-06). */
enum class Category(
    val kind: SpendingKind?,
) {
    FOOD(SpendingKind.LIFESTYLE),
    SHOPPING(SpendingKind.LIFESTYLE),
    HOUSING(SpendingKind.LIFESTYLE),
    BILLS(SpendingKind.LIFESTYLE),
    TRANSPORT(SpendingKind.TRAVEL),
    TRAVEL(SpendingKind.TRAVEL),
    OTHER(SpendingKind.LIFESTYLE),
    INVESTMENT(null),
    TRANSFER(null),
    INCOME(null),
    CASHBACK(null),
    ;

    val code: String get() = name.lowercase()

    companion object {
        fun parse(code: String): Category? = entries.firstOrNull { it.code == code }

        fun spending(): List<Category> = entries.filter { it.kind != null }
    }
}

enum class Channel {
    PROMPTPAY,
    TRANSFER,
    CARD,
    BILL,
    DEPOSIT,
    INTEREST,
    CASHBACK,
    SYSTEM,
    ;

    val code: String get() = name.lowercase()
}

enum class JournalType {
    OPENING,
    DEPOSIT,
    TRANSFER,
    BILL,
    CARD,
    FEE,
    INTEREST,
    CASHBACK,
    INVESTMENT,
    ;

    val code: String get() = name.lowercase()
}

enum class Direction {
    IN,
    OUT,
    ;

    companion object {
        fun parse(code: String): Direction? = entries.firstOrNull { it.name.equals(code, ignoreCase = true) }
    }
}

object InternalAccounts {
    /** Counterparty for money entering or leaving the bank; created by the V3 migration. */
    val CLEARING: java.util.UUID = java.util.UUID.fromString("00000000-0000-0000-0000-000000000001")
}
