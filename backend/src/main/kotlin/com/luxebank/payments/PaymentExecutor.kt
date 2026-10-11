package com.luxebank.payments

import com.luxebank.accounts.AccountQueries
import com.luxebank.accounts.AccountRow
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.integration.BillPaymentGateway
import com.luxebank.integration.ExternalAccount
import com.luxebank.integration.InterbankTransferGateway
import com.luxebank.ledger.Category
import com.luxebank.ledger.Channel
import com.luxebank.ledger.EntryDetails
import com.luxebank.ledger.InternalAccounts
import com.luxebank.ledger.JournalType
import com.luxebank.ledger.LedgerService
import com.luxebank.ledger.Line
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * The money-moving step of a confirmation, as one transaction on one connection (spec 7.2, 13.2):
 * consume the inquiry, lock the accounts, re-check the daily limit, post to the ledger, call the gateway
 * and record the payment. Any failure rolls all of it back, so the customer can retry with the same key.
 */
@Component
class PaymentExecutor(
    private val store: PaymentStore,
    private val accounts: AccountQueries,
    private val ledger: LedgerService,
    private val interbank: InterbankTransferGateway,
    private val bills: BillPaymentGateway,
    private val billers: BillerCatalog,
    private val payees: PayeeStore,
    private val clock: Clock,
) {
    /** Returns the payer's history row id. */
    @Transactional
    fun execute(
        inquiry: Inquiry,
        idempotencyHash: String,
        options: ConfirmOptions,
        english: Boolean,
    ): UUID {
        if (!store.consume(inquiry.id, Instant.now(clock))) {
            throw ApiException(ErrorCode.DUPLICATE_REQUEST, "This payment was already submitted")
        }
        // Customer accounts only, in the same id order as LedgerService, so postings cannot deadlock.
        store.lockAccounts(listOfNotNull(inquiry.fromAccountId, inquiry.toAccountId))
        val from = accounts.requireOwned(inquiry.userId, inquiry.fromAccountId)
        if (inquiry.kind == PaymentKind.TRANSFER && inquiry.recipientType != RecipientType.OWN) {
            checkDailyLimit(from, inquiry.amountSatang)
        }

        val entryId = post(inquiry, from, idempotencyHash, english)
        val transactionId = store.payerTransaction(entryId, from.id)
        store.insertPayment(inquiry.userId, inquiry.id, idempotencyHash, entryId, transactionId)

        if (inquiry.kind == PaymentKind.TRANSFER) payees.remember(inquiry, favorite = options.saveAsFavorite)
        if (options.saveBill && inquiry.kind == PaymentKind.BILL) billers.save(inquiry.userId, inquiry)
        return transactionId
    }

    fun checkDailyLimit(
        from: AccountRow,
        amount: Long,
    ) {
        val used = store.transferredToday(from.id, LocalDate.now(clock))
        if (used + amount > from.dailyTransferLimitSatang) {
            throw ApiException(ErrorCode.DAILY_LIMIT_EXCEEDED, "This transfer is over today's limit")
        }
    }

    private fun post(
        inquiry: Inquiry,
        from: AccountRow,
        idempotencyHash: String,
        english: Boolean,
    ): UUID {
        val amount = inquiry.amountSatang
        val shownName = if (inquiry.recipientType == RecipientType.OWN) inquiry.recipientName else Masking.name(inquiry.recipientName)
        val channel = if (inquiry.recipientType == RecipientType.PROMPTPAY) Channel.PROMPTPAY else Channel.TRANSFER
        val debit = Line(from.id, -amount, EntryDetails(shownName, Category.TRANSFER, channel, memo = inquiry.memo))

        return when (inquiry.recipientType) {
            RecipientType.OWN, RecipientType.INTERNAL -> {
                val to = checkNotNull(inquiry.toAccountId)
                val credit =
                    if (inquiry.recipientType == RecipientType.OWN) {
                        EntryDetails(from.name, Category.TRANSFER, Channel.TRANSFER, memo = inquiry.memo)
                    } else {
                        EntryDetails(
                            Masking.name(accounts.ownerName(inquiry.userId, english)),
                            Category.INCOME,
                            Channel.TRANSFER,
                            memo = inquiry.memo,
                        )
                    }
                ledger.post(JournalType.TRANSFER, listOf(debit, Line(to, amount, credit)), idempotencyKey = idempotencyHash)
            }
            RecipientType.OTHER_BANK, RecipientType.PROMPTPAY -> {
                val entry =
                    ledger.post(
                        JournalType.TRANSFER,
                        listOf(debit, Line(InternalAccounts.CLEARING, amount)),
                        idempotencyKey = idempotencyHash,
                    )
                val target = ExternalAccount(checkNotNull(inquiry.bankCode), checkNotNull(inquiry.accountOrProxy), inquiry.recipientName)
                // Inside the database transaction: a rejection rolls the debit back (production adds pending + reversal).
                interbank.transfer(target, amount, entry.toString())
                entry
            }
            RecipientType.BILL -> {
                val biller = billers.require(checkNotNull(inquiry.billerCode))
                val details = EntryDetails(biller.name(english), Category.BILLS, Channel.BILL, biller.monogram, inquiry.memo)
                val cardAccount = inquiry.toAccountId
                if (cardAccount != null) {
                    // A LuxeBank card paid from a LuxeBank account: settles inside the ledger, no bill gateway.
                    val credit = EntryDetails(from.name, Category.TRANSFER, Channel.BILL, memo = inquiry.memo)
                    return ledger.post(
                        JournalType.BILL,
                        listOf(Line(from.id, -amount, details), Line(cardAccount, amount, credit)),
                        idempotencyKey = idempotencyHash,
                    )
                }
                val entry =
                    ledger.post(
                        JournalType.BILL,
                        listOf(Line(from.id, -amount, details), Line(InternalAccounts.CLEARING, amount)),
                        idempotencyKey = idempotencyHash,
                    )
                bills.pay(biller.code, checkNotNull(inquiry.ref1), inquiry.ref2, amount, entry.toString())
                entry
            }
        }
    }
}
