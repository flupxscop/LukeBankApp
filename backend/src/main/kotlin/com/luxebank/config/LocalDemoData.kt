package com.luxebank.config

import com.luxebank.accounts.AccountQueries
import com.luxebank.common.security.SecretHasher
import com.luxebank.ledger.BankTime
import com.luxebank.ledger.Category
import com.luxebank.ledger.Channel
import com.luxebank.ledger.EntryDetails
import com.luxebank.ledger.InternalAccounts
import com.luxebank.ledger.JournalType
import com.luxebank.ledger.LedgerService
import com.luxebank.ledger.Line
import com.luxebank.users.User
import com.luxebank.users.UserRepository
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Component
import org.springframework.transaction.support.TransactionTemplate
import java.sql.Date
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import kotlin.random.Random

/**
 * Demo customer for local development only. Values are synthetic (spec 13.3.2):
 * citizen ID 1-2345-67890-12-1, password LuxeDemo#2026, OTP 000000.
 * Also seeds a year of deterministic ledger history so the home and history screens have real data (M2).
 * Literal amounts and dates are the fixture itself, hence the suppressed style rules.
 */
@Suppress("MagicNumber", "LongMethod", "CyclomaticComplexMethod", "LongParameterList")
@Component
@Profile("local")
class LocalDemoData(
    private val users: UserRepository,
    private val hasher: SecretHasher,
    private val accounts: AccountQueries,
    private val ledger: LedgerService,
    private val jdbc: NamedParameterJdbcTemplate,
    private val tx: TransactionTemplate,
    private val clock: Clock,
) : ApplicationRunner {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val citizenHash = hasher.identityHash(DEMO_CITIZEN_ID)
        val user =
            users.findByCitizenIdHash(citizenHash) ?: users.save(
                User(
                    citizenIdHash = citizenHash,
                    passwordHash = hasher.hashSecret(DEMO_PASSWORD),
                    phone = "0812344521",
                    firstNameTh = "นกน้อย",
                    firstNameEn = "Noknoi",
                    tier = "GOLD",
                ),
            )
        if (accounts.listForUser(user.id).isNotEmpty()) return
        tx.executeWithoutResult { seedLedger(user.id) }
        log.info("Created local demo customer with a year of history")
    }

    private fun seedLedger(userId: UUID) {
        val primary = createAccount(userId, "current", "บัญชีหลัก พรีเมียร์", "1234564289", primary = true)
        val savings = createAccount(userId, "savings", "ออมทรัพย์ เป้าหมาย", "1234567731", primary = false)
        val today = LocalDate.now(clock)
        val start = today.minusDays(HISTORY_DAYS)
        val firstMonth = start.withDayOfMonth(1)
        for (kind in listOf("lifestyle" to 5_000_000L, "travel" to 2_500_000L)) {
            jdbc.update(
                "INSERT INTO spending_budgets (id, user_id, kind, month, limit_satang) VALUES (:id, :user, :kind, :month, :limit)",
                mapOf(
                    "id" to UUID.randomUUID(),
                    "user" to userId,
                    "kind" to kind.first,
                    "month" to Date.valueOf(firstMonth),
                    "limit" to kind.second,
                ),
            )
        }
        jdbc.update(
            "INSERT INTO savings_goals (id, user_id, account_id, name, target_satang) VALUES (:id, :user, :account, :name, :target)",
            mapOf("id" to UUID.randomUUID(), "user" to userId, "account" to savings, "name" to "ทริปญี่ปุ่น", "target" to 24_000_000L),
        )

        val seeder = Seeder(primary, savings)
        seeder.external(JournalType.OPENING, primary, 320_000_000, at(start.minusDays(1), 9, 0), "ยอดยกมา", Category.INCOME, Channel.SYSTEM)
        seeder.external(JournalType.OPENING, savings, 9_000_000, at(start.minusDays(1), 9, 0), "ยอดยกมา", Category.INCOME, Channel.SYSTEM)

        val random = Random(SEED)
        var day = start
        while (!day.isAfter(today)) {
            seeder.day(day, today, random)
            day = day.plusDays(1)
        }
    }

    private inner class Seeder(
        val primary: UUID,
        val savings: UUID,
    ) {
        fun day(
            day: LocalDate,
            today: LocalDate,
            random: Random,
        ) {
            val isToday = day == today
            if (day.dayOfMonth == 1) {
                external(
                    JournalType.DEPOSIT,
                    primary,
                    18_500_000,
                    at(day, 7, 0),
                    "บริษัท ลักซ์ โฮลดิ้งส์",
                    Category.INCOME,
                    Channel.DEPOSIT,
                    "LH",
                )
            }
            if (day.dayOfMonth == 9) {
                val memo = "ค่าเช่าเดือน" + THAI_MONTHS[day.monthValue - 1]
                external(
                    JournalType.TRANSFER,
                    primary,
                    -2_850_000,
                    at(day, 9, 30),
                    "คอนโด เดอะ ริเวอร์",
                    Category.HOUSING,
                    Channel.PROMPTPAY,
                    memo = memo,
                )
            }
            if (day.dayOfMonth == 2) moveToSavings(day)
            if (day.dayOfMonth == 15) {
                external(
                    JournalType.BILL,
                    primary,
                    -random.amount(90_000, 260_000),
                    at(day, 20, 15),
                    "การไฟฟ้านครหลวง",
                    Category.BILLS,
                    Channel.BILL,
                    "MEA",
                )
                external(JournalType.BILL, primary, -159_900, at(day, 20, 16), "AIS Fibre", Category.BILLS, Channel.BILL, "AIS")
            }
            if (day.dayOfMonth == day.lengthOfMonth()) {
                external(
                    JournalType.INTEREST,
                    savings,
                    random.amount(8_000, 20_000),
                    at(day, 23, 0),
                    "ดอกเบี้ยเงินฝาก",
                    Category.INCOME,
                    Channel.INTEREST,
                )
            }
            if (day.dayOfWeek.value == 7) {
                external(
                    JournalType.CASHBACK,
                    primary,
                    random.amount(40_000, 180_000),
                    at(day, 10, 0),
                    "LuxeBank Cashback",
                    Category.CASHBACK,
                    Channel.CASHBACK,
                    "LB",
                )
            }
            if (day.dayOfWeek.value == 1 && random.nextInt(2) == 0) {
                external(JournalType.CARD, primary, -125_000, at(day, 8, 0), "BTS Rabbit", Category.TRANSPORT, Channel.CARD)
            }
            if (day.dayOfMonth % 14 == 8) {
                external(
                    JournalType.INVESTMENT,
                    primary,
                    random.amount(300_000, 1_500_000),
                    at(day, 14, 25),
                    "Wealth Plus",
                    Category.INVESTMENT,
                    Channel.TRANSFER,
                    "WP",
                )
            }
            if (random.nextInt(TRAVEL_ODDS) == 0) {
                val (name, code) = TRAVEL.random(random)
                external(
                    JournalType.CARD,
                    primary,
                    -random.amount(800_000, 2_500_000),
                    at(day, 11, 40),
                    name,
                    Category.TRAVEL,
                    Channel.CARD,
                    code,
                )
            }
            if (random.nextInt(3) == 0) {
                val (name, code) = SHOPS.random(random)
                external(
                    JournalType.CARD,
                    primary,
                    -random.amount(39_000, 680_000),
                    at(day, 16, 5),
                    name,
                    Category.SHOPPING,
                    Channel.CARD,
                    code,
                )
            }
            val meals = if (isToday) 1 else random.nextInt(1, 3)
            repeat(meals) { index ->
                val (name, code) = FOOD.random(random)
                val hour = if (index == 0 && isToday) 9 else listOf(8, 12, 19)[random.nextInt(3)]
                external(
                    JournalType.CARD,
                    primary,
                    -random.amount(9_000, 180_000),
                    at(day, hour, random.nextInt(60)),
                    name,
                    Category.FOOD,
                    Channel.CARD,
                    code,
                )
            }
        }

        private fun moveToSavings(day: LocalDate) {
            val amount = 1_500_000L
            ledger.post(
                JournalType.TRANSFER,
                listOf(
                    Line(primary, -amount, EntryDetails("ออมทรัพย์ เป้าหมาย", Category.TRANSFER, Channel.TRANSFER, memo = "ออมรายเดือน")),
                    Line(savings, amount, EntryDetails("จากบัญชีหลัก", Category.TRANSFER, Channel.TRANSFER, memo = "ออมรายเดือน")),
                ),
                at(day, 8, 5),
            )
        }

        fun external(
            type: JournalType,
            account: UUID,
            amount: Long,
            occurredAt: Instant,
            merchant: String,
            category: Category,
            channel: Channel,
            monogram: String? = null,
            memo: String? = null,
        ) {
            ledger.post(
                type,
                listOf(
                    Line(account, amount, EntryDetails(merchant, category, channel, monogram, memo)),
                    Line(InternalAccounts.CLEARING, -amount),
                ),
                occurredAt,
            )
        }
    }

    private fun createAccount(
        userId: UUID,
        type: String,
        name: String,
        number: String,
        primary: Boolean,
    ): UUID {
        val id = UUID.randomUUID()
        jdbc.update(
            """
            INSERT INTO accounts (id, user_id, type, name, account_number, is_primary)
            VALUES (:id, :user, :type, :name, :number, :primary)
            """,
            mapOf("id" to id, "user" to userId, "type" to type, "name" to name, "number" to number, "primary" to primary),
        )
        return id
    }

    private fun at(
        day: LocalDate,
        hour: Int,
        minute: Int,
    ): Instant = day.atTime(LocalTime.of(hour, minute)).atZone(BankTime.ZONE).toInstant()

    private fun Random.amount(
        min: Long,
        max: Long,
    ): Long = nextLong(min / ROUND, max / ROUND) * ROUND

    private companion object {
        const val DEMO_CITIZEN_ID = "1234567890121"
        const val DEMO_PASSWORD = "LuxeDemo#2026"
        const val HISTORY_DAYS = 365L
        const val SEED = 2026
        const val ROUND = 1_000L
        const val TRAVEL_ODDS = 40

        val THAI_MONTHS =
            listOf(
                "มกราคม",
                "กุมภาพันธ์",
                "มีนาคม",
                "เมษายน",
                "พฤษภาคม",
                "มิถุนายน",
                "กรกฎาคม",
                "สิงหาคม",
                "กันยายน",
                "ตุลาคม",
                "พฤศจิกายน",
                "ธันวาคม",
            )
        val FOOD =
            listOf(
                "Sarnies Bangkok" to "SB",
                "Roast Coffee" to "RC",
                "Gourmet Market" to "GM",
                "Starbucks" to "SB",
                "ร้านข้าวมันไก่ประตูน้ำ" to null,
            )
        val SHOPS = listOf("Central Chidlom" to "CC", "Uniqlo" to "UQ", "Apple Store" to null, "Lazada" to "LZ")
        val TRAVEL = listOf("Thai Airways" to "TG", "Agoda" to "AG", "Grab" to "GR")
    }
}
