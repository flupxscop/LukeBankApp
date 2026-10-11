package com.luxebank.ledger

import com.luxebank.TestcontainersConfiguration
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.support.TransactionTemplate
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors

@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class LedgerServiceTest(
    @Autowired private val ledger: LedgerService,
    @Autowired private val fixture: BankFixture,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
    @Autowired private val tx: TransactionTemplate,
) {
    @Test
    fun `balanced entry moves money, writes both read-model rows and stays reconciled`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 100_000)

        ledger.post(
            JournalType.TRANSFER,
            listOf(
                Line(customer.primary, -30_000, EntryDetails("ออมทรัพย์", Category.TRANSFER, Channel.TRANSFER)),
                Line(customer.savings, 30_000, EntryDetails("จากบัญชีหลัก", Category.TRANSFER, Channel.TRANSFER)),
            ),
        )

        assertThat(balance(customer.primary)).isEqualTo(70_000)
        assertThat(balance(customer.savings)).isEqualTo(30_000)
        assertThat(fixture.transactionIds(customer.primary)).hasSize(2)
        assertThat(fixture.transactionIds(customer.savings)).hasSize(1)
        assertThat(ledger.unreconciledAccounts()).isEmpty()
    }

    @Test
    fun `entries that do not sum to zero or have fewer than two lines are rejected`() {
        val customer = fixture.customer()
        val details = EntryDetails("x", Category.OTHER, Channel.SYSTEM)

        assertThatThrownBy {
            ledger.post(JournalType.FEE, listOf(Line(customer.primary, 100, details), Line(InternalAccounts.CLEARING, -99)))
        }.isInstanceOf(IllegalArgumentException::class.java)
        assertThatThrownBy { ledger.post(JournalType.FEE, listOf(Line(customer.primary, 0, details))) }
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThatThrownBy {
            ledger.post(JournalType.FEE, listOf(Line(customer.primary, 100), Line(InternalAccounts.CLEARING, -100)))
        }.isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun `overdraft is refused and leaves no trace`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 5_000)

        assertThatThrownBy { fixture.spend(customer.primary, 5_001) }
            .isInstanceOfSatisfying(ApiException::class.java) { assertThat(it.code).isEqualTo(ErrorCode.INSUFFICIENT_FUNDS) }

        assertThat(balance(customer.primary)).isEqualTo(5_000)
        assertThat(fixture.transactionIds(customer.primary)).hasSize(1)
    }

    @Test
    fun `unknown accounts and inactive accounts cannot be posted to`() {
        val customer = fixture.customer()
        val details = EntryDetails("x", Category.OTHER, Channel.SYSTEM)
        assertThatThrownBy {
            ledger.post(JournalType.FEE, listOf(Line(UUID.randomUUID(), 100, details), Line(InternalAccounts.CLEARING, -100)))
        }.isInstanceOfSatisfying(ApiException::class.java) { assertThat(it.code).isEqualTo(ErrorCode.NOT_FOUND) }

        jdbc.update("UPDATE accounts SET status = 'frozen' WHERE id = :id", mapOf("id" to customer.primary))
        assertThatThrownBy { fixture.deposit(customer.primary, 100) }
            .isInstanceOfSatisfying(ApiException::class.java) { assertThat(it.code).isEqualTo(ErrorCode.ACCOUNT_UNAVAILABLE) }
    }

    @Test
    fun `same idempotency key posts once`() {
        val customer = fixture.customer()
        val lines =
            listOf(
                Line(customer.primary, 1_000, EntryDetails("Payroll", Category.INCOME, Channel.DEPOSIT)),
                Line(InternalAccounts.CLEARING, -1_000),
            )
        val key = UUID.randomUUID().toString()

        val first = ledger.post(JournalType.DEPOSIT, lines, idempotencyKey = key)
        val second = ledger.post(JournalType.DEPOSIT, lines, idempotencyKey = key)

        assertThat(second).isEqualTo(first)
        assertThat(balance(customer.primary)).isEqualTo(1_000)
    }

    @Test
    fun `database rejects unbalanced entries, edited postings and negative customer balances`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 1_000)
        val entry = UUID.randomUUID()

        assertThatThrownBy {
            tx.executeWithoutResult {
                jdbc.update(
                    "INSERT INTO journal_entries (id, type, reference_no, occurred_at) VALUES (:id, 'fee', :ref, now())",
                    mapOf("id" to entry, "ref" to "T" + entry.toString().take(12)),
                )
                jdbc.update(
                    "INSERT INTO postings (journal_entry_id, account_id, amount_satang) VALUES (:id, :account, 500)",
                    mapOf("id" to entry, "account" to customer.primary),
                )
            }
        }.rootCause().hasMessageContaining("unbalanced")

        assertThatThrownBy {
            jdbc.update("UPDATE postings SET amount_satang = 1 WHERE account_id = :account", mapOf("account" to customer.primary))
        }.hasMessageContaining("append-only")
        assertThatThrownBy {
            jdbc.update("DELETE FROM postings WHERE account_id = :account", mapOf("account" to customer.primary))
        }.hasMessageContaining("append-only")
        assertThatThrownBy {
            jdbc.update("UPDATE accounts SET balance_satang = -1 WHERE id = :id", mapOf("id" to customer.primary))
        }.hasMessageContaining("chk_accounts_customer_balance")
    }

    @Test
    fun `reconciliation finds a tampered balance snapshot`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 1_000)
        jdbc.update("UPDATE accounts SET balance_satang = 999999 WHERE id = :id", mapOf("id" to customer.primary))

        assertThat(ledger.unreconciledAccounts()).contains(customer.primary)

        jdbc.update("UPDATE accounts SET balance_satang = 1000 WHERE id = :id", mapOf("id" to customer.primary))
        assertThat(ledger.unreconciledAccounts()).doesNotContain(customer.primary)
    }

    @Test
    fun `concurrent debits never overdraw the account`() {
        val customer = fixture.customer()
        fixture.deposit(customer.primary, 100)

        val pool = Executors.newFixedThreadPool(THREADS)
        val results =
            pool
                .invokeAll(
                    (1..THREADS).map { Callable { runCatching { fixture.spend(customer.primary, 30) }.isSuccess } },
                ).map { it.get() }
        pool.shutdown()

        assertThat(results.count { it }).isEqualTo(3)
        assertThat(balance(customer.primary)).isEqualTo(10)
        assertThat(ledger.unreconciledAccounts()).isEmpty()
    }

    private fun balance(account: UUID): Long =
        jdbc.queryForObject("SELECT balance_satang FROM accounts WHERE id = :id", mapOf("id" to account), Long::class.java) ?: 0

    private companion object {
        const val THREADS = 10
    }
}
