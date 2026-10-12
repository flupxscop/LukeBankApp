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
| Card processor | Issues test cards; PAN/CVV derived from the token (Luhn-valid test BINs), never stored; rules and blocks are accepted | `integration/stub/StubCardProcessor.kt` |
| Push notifications (APNs) | Logged (category and last 6 token characters only); the in-app inbox always receives the entry | `integration/stub/StubPushNotifier.kt` |
| RM chat, privileges, PDPA/terms text | Client-side only: chat stays on the phone with an automatic reply; static copy | `ios/LuxeBank/Features/Profile` |
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
| `CardProcessor` | `luxebank.integrations.cards` | `cards/CardService`, `config/LocalDemoData` |
| `PushNotifier` | `luxebank.integrations.push` | `notifications/NotificationService` |

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
- **Card purchases** arrive from the processor's authorisation feed; post them through `LedgerService.post` with
  `EntryDetails(cardId = …)` against the card's account (credit) or linked account (debit).
- **Real push (APNs)**: an adapter that signs a provider JWT with the APNs auth key (kept in a secrets manager),
  sends over HTTP/2 to `api.push.apple.com`, and clears `devices.push_token` when APNs answers `410 Unregistered`.
  The app also needs the Push Notifications capability (`aps-environment`) in a paid team's provisioning profile.
  Keep push text free of balances; it shows on the lock screen. For volume, move delivery from the in-process
  `@Async` listener to an outbox table plus a worker so a restart never loses a notification.
- **App health telemetry**: implement `TelemetrySink` (iOS, `Core/Telemetry/AppMetrics.swift`) to send the MetricKit
  `AppHealthReport` (counts and durations only) to the observability backend, and alert on crash-free sessions and
  hang rate per release (docs/app-quality-metrics.md).
- **RM chat** behind a messaging port (the RM's CRM or a chat vendor) instead of the on-device simulation.
- **Encrypting revealed card details to the device** (ECIES to a key-agreement key in the Secure Enclave).

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
