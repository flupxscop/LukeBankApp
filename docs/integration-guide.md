# LuxeBank — From simulation to a real system

LuxeBank is built as a **simulation** (SPEC D26): every external system is a stub and the app can run entirely
on mock data. The code is arranged so each piece can be made real on its own, without touching business logic.
This guide lists the seams and what replacing each one involves.

## 1. What is simulated today

| Area | Simulation | Where |
|---|---|---|
| SMS OTP | Logged, never sent; code `000000` in `local`/`test` | `integration/stub/StubAdapters.kt` |
| Other-bank transfers (ITMX) | Name lookup and transfer always succeed, except numbers ending `0000` (not found) and `9999` (rejected) | `integration/stub/PaymentStubs.kt` |
| PromptPay directory | Any valid mobile / national ID / e-wallet resolves to a stub person | `integration/stub/PaymentStubs.kt` |
| Bill payment aggregator | Stable amount due on the 25th per reference; all-zero references unknown | `integration/stub/PaymentStubs.kt` |
| Money outside LuxeBank | Posted to the internal `INT-CLEARING` account | `ledger/LedgerTypes.kt` (`InternalAccounts`) |
| Customer data | Demo customer, accounts and a year of history in profile `local` | `config/LocalDemoData.kt` |
| iOS data | `Mock*Repository` when no backend is configured (Debug only) | `ios/LuxeBank/Data/Mock` |

The core is **not** simulated: the double-entry ledger, limits, idempotency, device-bound signatures, PIN
lockout, audit trail and BOLA checks behave as they would in production and are covered by tests.

## 2. Backend: replace one external system

Each external system is a port (interface) in `backend/src/main/kotlin/com/luxebank/integration/Ports.kt`:

| Port | Config key | Called from |
|---|---|---|
| `OtpSender` | `luxebank.integrations.otp` | `auth/OtpService` |
| `InterbankTransferGateway` | `luxebank.integrations.interbank` | `payments/RecipientResolver`, `payments/PaymentExecutor` |
| `PromptPayDirectory` | `luxebank.integrations.promptpay` | `payments/RecipientResolver` |
| `BillPaymentGateway` | `luxebank.integrations.bills` | `payments/BillsController`, `payments/PaymentExecutor` |

Steps for, say, a real ITMX gateway:

1. Create `integration/itmx/ItmxInterbankGateway.kt` implementing `InterbankTransferGateway`.
2. Annotate it `@Component` and
   `@ConditionalOnProperty(prefix = "luxebank.integrations", name = ["interbank"], havingValue = "itmx")`.
3. Set `luxebank.integrations.interbank: itmx` for that environment. The stub switches itself off; every other
   system stays simulated.
4. Map provider failures to `ApiException(ErrorCode.SERVICE_UNAVAILABLE, …)`; the payment transaction then
   rolls back and the customer can retry with the same idempotency key.

The `prod` profile refuses to start while any `StubAdapter` bean is active (`ProductionAdapterGuard`).

### What a real gateway additionally needs

These are deliberately not built in the simulation. The schema and code leave room for them:

- **Timeouts and circuit breakers** around each adapter call (for example Resilience4j in the adapter itself).
- **Pending and reversal** for transfers whose outcome is unknown. Today the gateway call runs inside the
  payment transaction (`PaymentExecutor.post`). For a real network call, post the entry with
  `journal_entries.status = 'pending'` (already allowed by the schema), commit, call the gateway, then mark
  it `posted` or post a reversing entry. Postings are append-only, so a reversal is a new entry, never an edit.
- **Store the signed confirmation** (challenge + signature) for disputes (threat model R1).
- **Encrypted columns** for payee account numbers and references (SPEC 13.3).

## 3. Backend: make the bank side real

- **Customers and accounts** come from `LocalDemoData` only in profile `local`. A real core-banking feed
  would populate `users`, `accounts` and post opening balances through `LedgerService.post`, which is the
  only writer of money.
- **Fees** are ฿0 (D19). Add a fee line to the journal entry and an internal fee-income account when needed;
  the inquiry already carries `fee_satang`.
- **Secrets**: `LUXEBANK_PEPPER`, `LUXEBANK_IDENTITY_KEY` and the JWT key pair come from the environment;
  in production they come from a KMS (see `application.yml`).

## 4. iOS: point the app at a backend

| Build | Data source |
|---|---|
| Debug, no arguments | `MockAuthRepository`, `MockBankRepository`, `MockPaymentRepository` |
| Debug, `-LuxeBankAPI http://127.0.0.1:8080` | Remote repositories against the local Docker backend |
| Release | Remote repositories only; needs `LUXEBANK_API_BASE_URL` (HTTPS) and `LUXEBANK_API_PINS`, or it refuses to start |

The choice lives in `App/AppConfiguration.swift` and `App/AppEnvironment.swift`. Features depend only on the
repository protocols (`AuthRepository`, `DashboardRepository`, `TransactionRepository`, `PaymentRepository`),
so a new data source is one more implementation, not a change to screens or view models.

To build the simulated app for demos as a Release build, run the Docker backend somewhere reachable over
HTTPS and set those two build settings.

## 5. Checklist before connecting anything real

- Security audit and penetration test (SPEC M6, 13.4).
- Contracts and licences for each provider (SPEC D2).
- Hosting region and PDPA assessment (SPEC D5).
- Replace the placeholder sending-bank code `099` in slip QR codes with the ITMX member code (D21).
