package com.luxebank.ledger

import com.luxebank.auth.TestDeviceKey
import com.luxebank.auth.TokenService
import com.luxebank.common.security.SecretHasher
import com.luxebank.devices.Device
import com.luxebank.devices.DeviceRepository
import com.luxebank.users.User
import com.luxebank.users.UserRepository
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.stereotype.Component
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import kotlin.random.Random

/** Builds customers with accounts, a signed-in session and ledger history for integration tests. */
@Component
class BankFixture(
    private val users: UserRepository,
    private val devices: DeviceRepository,
    private val tokens: TokenService,
    private val hasher: SecretHasher,
    private val jdbc: NamedParameterJdbcTemplate,
    private val ledger: LedgerService,
    private val cards: com.luxebank.cards.CardStore,
    private val processor: com.luxebank.integration.CardProcessor,
) {
    data class Customer(
        val userId: UUID,
        val deviceId: UUID,
        val accessToken: String,
        val primary: UUID,
        val savings: UUID,
        val deviceKey: TestDeviceKey,
        val biometricKey: TestDeviceKey,
    )

    fun customer(
        withAccounts: Boolean = true,
        lastName: String = "ใจงาม",
    ): Customer {
        val user =
            users.save(
                User(
                    citizenIdHash = hasher.identityHash(digits(13)),
                    passwordHash = "unused",
                    phone = "0812344521",
                    firstNameTh = "นกน้อย",
                    firstNameEn = "Noknoi",
                    lastNameTh = lastName,
                    lastNameEn = "Jaingam",
                    tier = "GOLD",
                ),
            )
        val deviceKey = TestDeviceKey()
        val biometricKey = TestDeviceKey()
        val device =
            devices.save(
                Device(
                    userId = user.id,
                    deviceName = "Test",
                    publicKey = deviceKey.x963,
                    biometricPublicKey = biometricKey.x963,
                    pinHash = hasher.hashSecret(PIN),
                ),
            )
        val token = tokens.issue(user.id, device.id).accessToken
        if (!withAccounts) return Customer(user.id, device.id, token, UUID.randomUUID(), UUID.randomUUID(), deviceKey, biometricKey)
        val primary = account(user.id, "current", "บัญชีหลัก", primary = true)
        val savings = account(user.id, "savings", "ออมทรัพย์", primary = false)
        return Customer(user.id, device.id, token, primary, savings, deviceKey, biometricKey)
    }

    fun account(
        userId: UUID,
        type: String,
        name: String,
        primary: Boolean,
    ): UUID {
        val id = UUID.randomUUID()
        jdbc.update(
            """
            INSERT INTO accounts (id, user_id, type, name, account_number, is_primary)
            VALUES (:id, :user, :type, :name, :number, :primary)
            """,
            mapOf("id" to id, "user" to userId, "type" to type, "name" to name, "number" to digits(10), "primary" to primary),
        )
        return id
    }

    fun accountNumber(account: UUID): String =
        checkNotNull(
            jdbc.queryForObject("SELECT account_number FROM accounts WHERE id = :id", mapOf("id" to account), String::class.java),
        )

    fun balance(account: UUID): Long =
        jdbc.queryForObject("SELECT balance_satang FROM accounts WHERE id = :id", mapOf("id" to account), Long::class.java) ?: 0

    fun deposit(
        account: UUID,
        satang: Long,
        at: Instant = Instant.now(),
        merchant: String = "Payroll",
        category: Category = Category.INCOME,
    ): UUID = external(account, satang, at, merchant, category)

    fun spend(
        account: UUID,
        satang: Long,
        at: Instant = Instant.now(),
        merchant: String = "Sarnies Bangkok",
        category: Category = Category.FOOD,
        memo: String? = null,
    ): UUID = external(account, -satang, at, merchant, category, memo)

    fun budget(
        userId: UUID,
        kind: SpendingKind,
        month: LocalDate,
        satang: Long,
    ) {
        jdbc.update(
            "INSERT INTO spending_budgets (id, user_id, kind, month, limit_satang) VALUES (:id, :user, :kind, :month, :limit)",
            mapOf(
                "id" to UUID.randomUUID(),
                "user" to userId,
                "kind" to kind.code,
                "month" to java.sql.Date.valueOf(month),
                "limit" to satang,
            ),
        )
    }

    fun at(
        day: LocalDate,
        hour: Int = 12,
    ): Instant = day.atTime(LocalTime.of(hour, 0)).atZone(BankTime.ZONE).toInstant()

    fun transactionIds(account: UUID): List<UUID> =
        jdbc.query(
            "SELECT id FROM transactions WHERE account_id = :account ORDER BY occurred_at DESC, id DESC",
            mapOf("account" to account),
        ) { rs, _ -> rs.getObject(1, UUID::class.java) }

    private fun external(
        account: UUID,
        satang: Long,
        at: Instant,
        merchant: String,
        category: Category,
        memo: String? = null,
    ): UUID =
        ledger.post(
            JournalType.CARD,
            listOf(
                Line(account, satang, EntryDetails(merchant, category, Channel.CARD, memo = memo)),
                Line(InternalAccounts.CLEARING, -satang),
            ),
            at,
        )

    /** A debit card on the primary account, or a credit card with its own credit account and [creditLimit]. */
    fun card(
        customer: Customer,
        credit: Boolean,
        creditLimit: Long = 50_000_000,
        rewardPoints: Long = 0,
    ): UUID {
        val accountId =
            if (credit) {
                UUID.randomUUID().also { id ->
                    jdbc.update(
                        """
                        INSERT INTO accounts (id, user_id, type, name, account_number, is_primary, credit_limit_satang)
                        VALUES (:id, :user, 'credit', 'Titanium Reserve', :number, FALSE, :limit)
                        """,
                        mapOf("id" to id, "user" to customer.userId, "number" to digits(16), "limit" to creditLimit),
                    )
                }
            } else {
                customer.primary
            }
        val issued = processor.issue(credit, if (credit) "Titanium Reserve" else "LuxeBank Debit")
        return cards.insert(
            com.luxebank.cards.NewCard(
                userId = customer.userId,
                accountId = accountId,
                credit = credit,
                productName = if (credit) "Titanium Reserve" else "LuxeBank Debit",
                last4 = issued.last4,
                tokenRef = issued.tokenRef,
                expiryMonth = issued.expiryMonth,
                expiryYear = issued.expiryYear,
                dailyLimitSatang = 5_000_000,
                maxDailyLimitSatang = 20_000_000,
                rewardPoints = rewardPoints,
            ),
        )
    }

    fun cardAccount(cardId: UUID): UUID =
        checkNotNull(jdbc.queryForObject("SELECT account_id FROM cards WHERE id = :id", mapOf("id" to cardId), UUID::class.java))

    /** A purchase with [cardId] at a merchant, debiting the card's account. */
    fun purchase(
        cardId: UUID,
        satang: Long,
        merchant: String = "Sarnies Bangkok",
    ): UUID =
        ledger.post(
            JournalType.CARD,
            listOf(
                Line(cardAccount(cardId), -satang, EntryDetails(merchant, Category.FOOD, Channel.CARD, cardId = cardId)),
                Line(InternalAccounts.CLEARING, satang),
            ),
        )

    companion object {
        const val PIN = "482193"
    }

    private fun digits(count: Int) = (1..count).joinToString("") { Random.nextInt(10).toString() }
}
