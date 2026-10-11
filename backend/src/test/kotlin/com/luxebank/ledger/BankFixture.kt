package com.luxebank.ledger

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
) {
    data class Customer(
        val userId: UUID,
        val accessToken: String,
        val primary: UUID,
        val savings: UUID,
    )

    fun customer(withAccounts: Boolean = true): Customer {
        val user =
            users.save(
                User(
                    citizenIdHash = hasher.identityHash(digits(13)),
                    passwordHash = "unused",
                    phone = "0812344521",
                    firstNameTh = "นกน้อย",
                    firstNameEn = "Noknoi",
                    tier = "GOLD",
                ),
            )
        val device = devices.save(Device(userId = user.id, deviceName = "Test", publicKey = ByteArray(65), pinHash = "unused"))
        val token = tokens.issue(user.id, device.id).accessToken
        if (!withAccounts) return Customer(user.id, token, UUID.randomUUID(), UUID.randomUUID())
        val primary = account(user.id, "current", "บัญชีหลัก", primary = true)
        val savings = account(user.id, "savings", "ออมทรัพย์", primary = false)
        return Customer(user.id, token, primary, savings)
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

    private fun digits(count: Int) = (1..count).joinToString("") { Random.nextInt(10).toString() }
}
