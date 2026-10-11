package com.luxebank.payments

import com.luxebank.TestcontainersConfiguration
import com.luxebank.ledger.BankFixture
import com.luxebank.ledger.LedgerService
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActionsDsl
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import tools.jackson.databind.JsonNode
import tools.jackson.databind.ObjectMapper
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class PaymentFlowIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val fixture: BankFixture,
    @Autowired private val ledger: LedgerService,
    @Autowired private val jdbc: NamedParameterJdbcTemplate,
) {
    private fun funded(satang: Long = 100_000_000): BankFixture.Customer = fixture.customer().also { fixture.deposit(it.primary, satang) }

    // MARK: Transfers

    @Test
    fun `own-account transfer moves money, returns a verifiable slip and does not use the daily limit`() {
        val customer = funded()
        val inquiry = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "1500.50", memo = "ออม")
        assertThat(inquiry["to"]["name"].asString()).isEqualTo("ออมทรัพย์")
        assertThat(inquiry["fee"].asString()).isEqualTo("0.00")
        assertThat(inquiry["requiresBiometric"].asBoolean()).isFalse()

        val slip = confirmTransfer(customer, inquiry).andExpect { status { isOk() } }.json()

        assertThat(fixture.balance(customer.primary)).isEqualTo(100_000_000 - 150_050)
        assertThat(fixture.balance(customer.savings)).isEqualTo(150_050)
        assertThat(slip["amount"].asString()).isEqualTo("1500.50")
        assertThat(slip["from"]["name"].asString()).isEqualTo("นกน้อย ใจ**")
        assertThat(slip["from"]["account"].asString()).matches("x\\d{4}")
        val qr = slip["slipQr"].asString()
        assertThat(qr).contains(slip["referenceNo"].asString()).contains("5102TH")
        assertThat(ThaiQr.crc(qr.dropLast(4))).isEqualTo(qr.takeLast(4))

        val transactionId = slip["transactionId"].asString()
        get("/api/v1/transactions/$transactionId", customer).andExpect { jsonPath("$.hasSlip") { value(true) } }
        get(
            "/api/v1/transactions/$transactionId/slip",
            customer,
        ).andExpect { jsonPath("$.referenceNo") { value(slip["referenceNo"].asString()) } }
        get("/api/v1/transfers/limits", customer).andExpect { jsonPath("$.usedToday") { value("0.00") } }
        assertThat(ledger.unreconciledAccounts()).isEmpty()
    }

    @Test
    fun `transfer to another LuxeBank customer shows a masked name, credits them and remembers the payee`() {
        val payer = funded()
        val payee = fixture.customer(lastName = "รักดี")
        val number = fixture.accountNumber(payee.primary)

        val inquiry = transferInquiry(payer, mapOf("type" to "internal", "accountNumber" to number), "250")
        assertThat(inquiry["to"]["name"].asString()).isEqualTo("นกน้อย รั**")
        assertThat(inquiry["to"]["account"].asString()).isEqualTo("x" + number.takeLast(4))
        confirmTransfer(payer, inquiry, saveAsFavorite = true).andExpect { status { isOk() } }

        assertThat(fixture.balance(payee.primary)).isEqualTo(25_000)
        val credit = get("/api/v1/accounts/${payee.primary}/transactions", payee).json()["items"][0]
        assertThat(credit["category"].asString()).isEqualTo("income")
        assertThat(credit["merchant"].asString()).isEqualTo("นกน้อย ใจ**")

        val payees = get("/api/v1/payees", payer).json()
        assertThat(payees).hasSize(1)
        assertThat(payees[0]["favorite"].asBoolean()).isTrue()
        assertThat(payees[0]["account"].asString()).isEqualTo("x" + number.takeLast(4))
        assertThat(payees[0].toString()).doesNotContain(number)

        val again = transferInquiry(payer, mapOf("type" to "payee", "payeeId" to payees[0]["id"].asString()), "100")
        assertThat(again["recipientType"].asString()).isEqualTo("internal")
        get("/api/v1/transfers/limits", payer).andExpect { jsonPath("$.usedToday") { value("250.00") } }
    }

    @Test
    fun `other-bank and PromptPay transfers go through the stub gateways`() {
        val customer = funded()

        val other =
            transferInquiry(customer, mapOf("type" to "other_bank", "bankCode" to "KBANK", "accountNumber" to "123-4-56789-0"), "75")
        assertThat(other["to"]["bankName"].asString()).isEqualTo("กสิกรไทย")
        assertThat(other["to"]["name"].asString()).endsWith("**")
        confirmTransfer(customer, other).andExpect { status { isOk() } }

        val promptPay = transferInquiry(customer, mapOf("type" to "promptpay", "proxy" to "081-234-5678"), "25")
        assertThat(promptPay["recipientType"].asString()).isEqualTo("promptpay")
        confirmTransfer(customer, promptPay).andExpect { status { isOk() } }

        assertThat(fixture.balance(customer.primary)).isEqualTo(100_000_000 - 10_000)
        val channels =
            get("/api/v1/accounts/${customer.primary}/transactions", customer).json()["items"].map<JsonNode, String> {
                it["channel"].asString()
            }
        assertThat(channels).contains("promptpay", "transfer")
        assertThat(ledger.unreconciledAccounts()).isEmpty()
    }

    @Test
    fun `unknown recipients, bad proxies and a rejecting bank never move money`() {
        val customer = funded()
        inquiryRequest(customer, mapOf("type" to "other_bank", "bankCode" to "SCB", "accountNumber" to "1234560000"), "10")
            .andExpect { jsonPath("$.error.code") { value("RECIPIENT_NOT_FOUND") } }
        inquiryRequest(customer, mapOf("type" to "promptpay", "proxy" to "1234567890123"), "10")
            .andExpect { jsonPath("$.error.code") { value("VALIDATION_FAILED") } }
        inquiryRequest(customer, mapOf("type" to "other_bank", "bankCode" to "LUXE", "accountNumber" to "1234567890"), "10")
            .andExpect { status { isBadRequest() } }
        inquiryRequest(customer, mapOf("type" to "own", "accountId" to customer.primary), "10").andExpect { status { isBadRequest() } }

        val rejected = transferInquiry(customer, mapOf("type" to "other_bank", "bankCode" to "BBL", "accountNumber" to "1234569999"), "10")
        val key = UUID.randomUUID().toString()
        confirmTransfer(customer, rejected, key = key).andExpect { jsonPath("$.error.code") { value("SERVICE_UNAVAILABLE") } }
        assertThat(fixture.balance(customer.primary)).isEqualTo(100_000_000)
        // The inquiry is still usable, so the app can retry with the same key.
        confirmTransfer(customer, rejected, key = key).andExpect { jsonPath("$.error.code") { value("SERVICE_UNAVAILABLE") } }
    }

    @Test
    fun `the same idempotency key pays once, other reuse is refused`() {
        val customer = funded()
        val inquiry = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "100")
        val key = UUID.randomUUID().toString()

        val first = confirmTransfer(customer, inquiry, key = key).andExpect { status { isOk() } }.json()
        val retry = confirmTransfer(customer, inquiry, key = key).andExpect { status { isOk() } }.json()
        assertThat(retry["referenceNo"].asString()).isEqualTo(first["referenceNo"].asString())
        assertThat(fixture.balance(customer.savings)).isEqualTo(10_000)

        confirmTransfer(customer, inquiry, key = UUID.randomUUID().toString()).andExpect {
            status { isConflict() }
            jsonPath("$.error.code") { value("DUPLICATE_REQUEST") }
        }
        val other = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "100")
        confirmTransfer(customer, other, key = key).andExpect { jsonPath("$.error.code") { value("DUPLICATE_REQUEST") } }
        mockMvc
            .post("/api/v1/transfers") {
                bearer(customer)
                contentType = MediaType.APPLICATION_JSON
                content = objectMapper.writeValueAsString(confirmBody(customer, other))
            }.andExpect { status { isBadRequest() } }
    }

    @Test
    fun `amounts are validated against format, balance and the daily limit`() {
        val customer = funded(1_000_000)
        val own = mapOf("type" to "own", "accountId" to customer.savings)
        listOf("0", "-1", "1.001", "abc", "", "1e5").forEach { amount ->
            inquiryRequest(customer, own, amount).andExpect { jsonPath("$.error.code") { value("VALIDATION_FAILED") } }
        }
        inquiryRequest(customer, own, "10000.01").andExpect {
            status { isUnprocessableContent() }
            jsonPath("$.error.code") { value("INSUFFICIENT_FUNDS") }
        }

        jdbc.update("UPDATE accounts SET daily_transfer_limit_satang = 50000 WHERE id = :id", mapOf("id" to customer.primary))
        val promptPay = mapOf("type" to "promptpay", "proxy" to "0812345678")
        confirmTransfer(customer, transferInquiry(customer, promptPay, "400")).andExpect { status { isOk() } }
        inquiryRequest(customer, promptPay, "100.01").andExpect { jsonPath("$.error.code") { value("DAILY_LIMIT_EXCEEDED") } }
        // Own-account moves are not limited.
        transferInquiry(customer, own, "1000")
    }

    @Test
    fun `from 50,000 baht a transfer needs Face ID`() {
        val customer = funded(10_000_000)
        val inquiry = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "50000")
        assertThat(inquiry["requiresBiometric"].asBoolean()).isTrue()

        confirmTransfer(customer, inquiry).andExpect {
            status { isForbidden() }
            jsonPath("$.error.code") { value("STEP_UP_REQUIRED") }
        }
        confirmTransfer(customer, inquiry, biometric = true).andExpect { status { isOk() } }
        assertThat(fixture.balance(customer.savings)).isEqualTo(5_000_000)
    }

    @Test
    fun `wrong PIN, wrong signature and expired inquiries are refused without moving money`() {
        val customer = funded()
        val inquiry = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "100")

        confirmTransfer(customer, inquiry, pin = "111222").andExpect {
            jsonPath("$.error.code") { value("PIN_INVALID") }
            jsonPath("$.error.remainingAttempts") { value(4) }
        }
        val forged =
            confirmBody(customer, inquiry) +
                mapOf(
                    "signature" to
                        com.luxebank.auth
                            .TestDeviceKey()
                            .signBase64(inquiry["challenge"].asString()),
                )
        confirm("/api/v1/transfers", customer, forged, UUID.randomUUID().toString()).andExpect {
            jsonPath("$.error.code") { value("SIGNATURE_INVALID") }
        }

        jdbc.update("UPDATE payment_inquiries SET expires_at = now() - interval '1 second' WHERE id = :id", mapOf("id" to inquiry.id()))
        confirmTransfer(customer, inquiry).andExpect {
            status { isGone() }
            jsonPath("$.error.code") { value("INQUIRY_EXPIRED") }
        }
        assertThat(fixture.balance(customer.primary)).isEqualTo(100_000_000)
    }

    @Test
    fun `five wrong PINs on a payment lock the device`() {
        val customer = funded()
        val inquiry = transferInquiry(customer, mapOf("type" to "own", "accountId" to customer.savings), "100")
        repeat(4) { confirmTransfer(customer, inquiry, pin = "111222").andExpect { jsonPath("$.error.code") { value("PIN_INVALID") } } }
        confirmTransfer(customer, inquiry, pin = "111222").andExpect { jsonPath("$.error.code") { value("PIN_LOCKED") } }
        confirmTransfer(customer, inquiry).andExpect { jsonPath("$.error.code") { value("PIN_LOCKED") } }
    }

    @Test
    fun `another customer's accounts, inquiries, slips and payees are not found (BOLA)`() {
        val owner = funded()
        val intruder = funded()
        val inquiry = transferInquiry(owner, mapOf("type" to "own", "accountId" to owner.savings), "100")
        val slip = confirmTransfer(owner, inquiry).json()

        inquiryRequest(intruder, mapOf("type" to "own", "accountId" to owner.savings), "1").andExpect { status { isNotFound() } }
        mockMvc
            .post("/api/v1/transfers/inquiry") {
                bearer(intruder)
                contentType = MediaType.APPLICATION_JSON
                content =
                    objectMapper.writeValueAsString(
                        mapOf(
                            "fromAccountId" to owner.primary,
                            "recipient" to mapOf("type" to "own", "accountId" to intruder.savings),
                            "amount" to "1",
                        ),
                    )
            }.andExpect { status { isNotFound() } }
        val other = transferInquiry(owner, mapOf("type" to "own", "accountId" to owner.savings), "100")
        confirm(
            "/api/v1/transfers",
            intruder,
            confirmBody(intruder, other),
            UUID.randomUUID().toString(),
        ).andExpect { status { isNotFound() } }
        get("/api/v1/transactions/${slip["transactionId"].asString()}/slip", intruder).andExpect { status { isNotFound() } }

        val payee = funded()
        confirmTransfer(
            owner,
            transferInquiry(owner, mapOf("type" to "internal", "accountNumber" to fixture.accountNumber(payee.primary)), "1"),
        )
        val payeeId = get("/api/v1/payees", owner).json()[0]["id"].asString()
        mockMvc.delete("/api/v1/payees/$payeeId") { bearer(intruder) }.andExpect { status { isNotFound() } }
        inquiryRequest(intruder, mapOf("type" to "payee", "payeeId" to payeeId), "1").andExpect { status { isNotFound() } }
    }

    @Test
    fun `payees can be renamed, unfavourited and deleted`() {
        val owner = funded()
        val target = funded()
        confirmTransfer(
            owner,
            transferInquiry(owner, mapOf("type" to "internal", "accountNumber" to fixture.accountNumber(target.primary)), "1"),
        )
        val id = get("/api/v1/payees", owner).json()[0]["id"].asString()

        mockMvc
            .put("/api/v1/payees/$id") {
                bearer(owner)
                contentType = MediaType.APPLICATION_JSON
                content = """{"favorite":true,"nickname":"แม่"}"""
            }.andExpect {
                status { isOk() }
                jsonPath("$.nickname") { value("แม่") }
                jsonPath("$.favorite") { value(true) }
            }
        mockMvc.delete("/api/v1/payees/$id") { bearer(owner) }.andExpect { status { isNoContent() } }
        assertThat(get("/api/v1/payees", owner).json()).isEmpty()
    }

    @Test
    fun `concurrent confirmations racing other postings on the same account all succeed`() {
        // More payments than pooled connections, interleaved with ledger deposits into the payer's account:
        // guards against connection-pool starvation and lock-order deadlocks.
        val customer = funded()
        val bodies =
            (1..12).map {
                confirmBody(customer, transferInquiry(customer, mapOf("type" to "promptpay", "proxy" to "0812345678"), "1"))
            }
        val pool =
            java.util.concurrent.Executors
                .newFixedThreadPool(24)
        val confirms =
            bodies.map { body ->
                java.util.concurrent.Callable {
                    confirm("/api/v1/transfers", customer, body, UUID.randomUUID().toString()).andReturn().response.status
                }
            }
        val deposits =
            (1..12).map {
                java.util.concurrent.Callable { runCatching { fixture.deposit(customer.primary, 100) }.fold({ 200 }, { 500 }) }
            }
        val statuses = pool.invokeAll(confirms + deposits).map { it.get() }
        pool.shutdown()

        assertThat(statuses).containsOnly(200)
        assertThat(fixture.balance(customer.primary)).isEqualTo(100_000_000 - 12 * 100 + 12 * 100)
        assertThat(ledger.unreconciledAccounts()).isEmpty()
    }

    @Test
    fun `name inquiries are rate limited per customer`() {
        val customer = funded()
        repeat(30) { inquiryRequest(customer, mapOf("type" to "promptpay", "proxy" to "0812345678"), "1") }
        inquiryRequest(customer, mapOf("type" to "promptpay", "proxy" to "0812345678"), "1").andExpect {
            status { isTooManyRequests() }
            jsonPath("$.error.code") { value("RATE_LIMITED") }
        }
    }

    // MARK: Bills

    @Test
    fun `bill inquiry, payment, saved bill and paying a saved bill`() {
        val customer = funded()
        val billers = get("/api/v1/billers", customer, "category" to "electricity").json()
        assertThat(billers.map<JsonNode, String> { it["code"].asString() }).containsExactlyInAnyOrder("MEA", "PEA")

        val inquiry = billInquiry(customer, mapOf("billerCode" to "MEA", "ref1" to "0123456789")).andExpect { status { isOk() } }.json()
        assertThat(inquiry["bill"]["billerName"].asString()).isEqualTo("การไฟฟ้านครหลวง")
        assertThat(inquiry["bill"]["customerName"].asString()).endsWith("**")
        assertThat(inquiry["bill"]["dueDate"].isNull).isFalse()
        val due = inquiry["amount"].asString()

        confirm(
            "/api/v1/bills/payments",
            customer,
            confirmBody(customer, inquiry) + mapOf("saveBill" to true),
            UUID.randomUUID().toString(),
        ).andExpect {
            status { isOk() }
            jsonPath("$.bill.billerCode") { value("MEA") }
        }
        val history = get("/api/v1/accounts/${customer.primary}/transactions", customer).json()["items"][0]
        assertThat(history["category"].asString()).isEqualTo("bills")
        assertThat(history["amount"].asString()).isEqualTo("-$due")

        val saved = get("/api/v1/bills/saved", customer).json()
        assertThat(saved).hasSize(1)
        assertThat(saved[0]["paid"].asBoolean()).isTrue()
        assertThat(saved[0]["ref1"].asString()).isEqualTo("x6789")

        billInquiry(customer, mapOf("savedBillId" to saved[0]["id"].asString(), "amount" to "100")).andExpect { status { isOk() } }
        mockMvc.delete("/api/v1/bills/saved/${saved[0]["id"].asString()}") { bearer(customer) }.andExpect { status { isNoContent() } }
    }

    @Test
    fun `top-ups need an amount, unknown references fail and bills cannot be confirmed as transfers`() {
        val customer = funded()
        billInquiry(customer, mapOf("billerCode" to "AISTOP", "ref1" to "0812345678")).andExpect { status { isBadRequest() } }
        billInquiry(customer, mapOf("billerCode" to "AISTOP", "ref1" to "0812345678", "amount" to "300")).andExpect { status { isOk() } }
        billInquiry(customer, mapOf("billerCode" to "MEA", "ref1" to "0000000000")).andExpect {
            jsonPath("$.error.code") { value("BILL_NOT_FOUND") }
        }
        billInquiry(customer, mapOf("billerCode" to "NOPE", "ref1" to "1")).andExpect { status { isNotFound() } }
        billInquiry(customer, mapOf("billerCode" to "MEA", "ref1" to "12-34")).andExpect { status { isBadRequest() } }

        val bill = billInquiry(customer, mapOf("billerCode" to "MWA", "ref1" to "55667788")).json()
        confirm(
            "/api/v1/transfers",
            customer,
            confirmBody(customer, bill),
            UUID.randomUUID().toString(),
        ).andExpect { status { isNotFound() } }
    }

    // MARK: QR

    @Test
    fun `Thai QR codes are parsed for PromptPay and bills, tampered ones are rejected`() {
        val customer = funded()
        val promptPay =
            qr(
                SlipQr.tlv("29", SlipQr.tlv("00", "A000000677010111") + SlipQr.tlv("01", "0066812345678")) + SlipQr.tlv("54", "120.50"),
            )
        parseQr(customer, promptPay).andExpect {
            status { isOk() }
            jsonPath("$.type") { value("promptpay") }
            jsonPath("$.proxy") { value("0812345678") }
            jsonPath("$.amount") { value("120.50") }
        }

        val bill =
            qr(
                SlipQr.tlv(
                    "30",
                    SlipQr.tlv("00", "A000000677010112") + SlipQr.tlv("01", "099000000000101") + SlipQr.tlv("02", "0123456789"),
                ),
            )
        parseQr(customer, bill).andExpect {
            jsonPath("$.type") { value("bill") }
            jsonPath("$.billerCode") { value("MEA") }
            jsonPath("$.ref1") { value("0123456789") }
            jsonPath("$.amount") { doesNotExist() }
        }

        val tampered = promptPay.replace("120.50", "999.50")
        parseQr(customer, tampered).andExpect { jsonPath("$.error.code") { value("QR_INVALID") } }
        parseQr(customer, "hello").andExpect { jsonPath("$.error.code") { value("QR_INVALID") } }
        val unknownBiller =
            qr(
                SlipQr.tlv(
                    "30",
                    SlipQr.tlv("00", "A000000677010112") + SlipQr.tlv("01", "011111111111111") + SlipQr.tlv("02", "1"),
                ),
            )
        parseQr(customer, unknownBiller).andExpect { jsonPath("$.error.code") { value("QR_INVALID") } }
    }

    // MARK: Helpers

    private fun qr(fields: String): String {
        val body = SlipQr.tlv("00", "01") + SlipQr.tlv("01", "12") + fields + SlipQr.tlv("53", "764") + SlipQr.tlv("58", "TH") + "6304"
        return body + ThaiQr.crc(body)
    }

    private fun parseQr(
        customer: BankFixture.Customer,
        payload: String,
    ) = mockMvc.post("/api/v1/qr/parse") {
        bearer(customer)
        contentType = MediaType.APPLICATION_JSON
        content = objectMapper.writeValueAsString(mapOf("payload" to payload))
    }

    private fun inquiryRequest(
        customer: BankFixture.Customer,
        recipient: Map<String, Any?>,
        amount: String,
        memo: String? = null,
    ): ResultActionsDsl =
        mockMvc.post("/api/v1/transfers/inquiry") {
            bearer(customer)
            contentType = MediaType.APPLICATION_JSON
            content =
                objectMapper.writeValueAsString(
                    mapOf(
                        "fromAccountId" to customer.primary,
                        "recipient" to recipient,
                        "amount" to amount,
                        "memo" to memo,
                    ),
                )
        }

    private fun transferInquiry(
        customer: BankFixture.Customer,
        recipient: Map<String, Any?>,
        amount: String,
        memo: String? = null,
    ): JsonNode = inquiryRequest(customer, recipient, amount, memo).andExpect { status { isOk() } }.json()

    private fun billInquiry(
        customer: BankFixture.Customer,
        body: Map<String, Any?>,
    ): ResultActionsDsl =
        mockMvc.post("/api/v1/bills/inquiry") {
            bearer(customer)
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(mapOf("fromAccountId" to customer.primary) + body)
        }

    private fun confirmBody(
        customer: BankFixture.Customer,
        inquiry: JsonNode,
        biometric: Boolean = false,
        pin: String = BankFixture.PIN,
    ): Map<String, Any?> {
        val key = if (biometric) customer.biometricKey else customer.deviceKey
        return mapOf(
            "inquiryId" to inquiry.id(),
            "method" to if (biometric) "BIOMETRIC" else "PIN",
            "pin" to if (biometric) null else pin,
            "signature" to key.signBase64(inquiry["challenge"].asString()),
        )
    }

    private fun confirmTransfer(
        customer: BankFixture.Customer,
        inquiry: JsonNode,
        key: String = UUID.randomUUID().toString(),
        biometric: Boolean = false,
        pin: String = BankFixture.PIN,
        saveAsFavorite: Boolean = false,
    ): ResultActionsDsl =
        confirm(
            "/api/v1/transfers",
            customer,
            confirmBody(customer, inquiry, biometric, pin) + mapOf("saveAsFavorite" to saveAsFavorite),
            key,
        )

    private fun confirm(
        path: String,
        customer: BankFixture.Customer,
        body: Map<String, Any?>,
        key: String,
    ): ResultActionsDsl =
        mockMvc.post(path) {
            bearer(customer)
            header("Idempotency-Key", key)
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(body)
        }

    private fun get(
        path: String,
        customer: BankFixture.Customer,
        vararg params: Pair<String, String>,
    ): ResultActionsDsl =
        mockMvc.get(path) {
            bearer(customer)
            params.forEach { (name, value) -> param(name, value) }
        }

    private fun org.springframework.test.web.servlet.MockHttpServletRequestDsl.bearer(customer: BankFixture.Customer) =
        header("Authorization", "Bearer ${customer.accessToken}")

    private fun JsonNode.id(): UUID = UUID.fromString(this["inquiryId"].asString())

    private fun ResultActionsDsl.json(): JsonNode = objectMapper.readTree(andReturn().response.contentAsString)
}
