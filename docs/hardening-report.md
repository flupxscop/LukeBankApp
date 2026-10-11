# LuxeBank — M6 Hardening Report

| Field | Value |
|---|---|
| Milestone | M6 Hardening (SPEC section 12) |
| Date | 2026-10-11 |
| Scope | Simulation (SPEC D26): iOS app + `/api/v1` backend with stub adapters |
| Exit criterion | Ready to release on stub/staging |

Pen testing by an outside party, production hosting, real providers and regulator approval belong to M7 and are
out of scope (D26). Everything below is automated and runs in CI unless marked *manual*.

## 1. Security test cases (SPEC 13.4.4)

| Case | Covered by |
|---|---|
| Another customer's accounts, cards or transactions answer 404 (BOLA) | `HistoryIntegrationTest` "another customer's accounts and transactions…", `PaymentFlowIntegrationTest` "another customer's accounts, inquiries, slips and payees…", `CardsIntegrationTest` "another customer's cards…", `ProfileNotificationsIntegrationTest` "…other customers' notifications are not found" |
| Same idempotency key never debits twice | `LedgerServiceTest` "same idempotency key posts once", `PaymentFlowIntegrationTest` "the same idempotency key pays once, other reuse is refused" |
| Expired inquiry or changed amount is refused | `PaymentFlowIntegrationTest` "wrong PIN, wrong signature and expired inquiries are refused…"; the confirm request carries only the inquiry id, so the amount cannot be changed after the inquiry |
| Negative, zero, over-balance, over-limit or 3-decimal amounts are refused | `PaymentUnitTest` "amounts parse to satang and reject anything ambiguous", `PaymentFlowIntegrationTest` "amounts are validated against format, balance and the daily limit", `LedgerServiceTest` "overdraft is refused…" |
| ฿50,000 or more without step-up gets `STEP_UP_REQUIRED` | `PaymentFlowIntegrationTest` "from 50,000 baht a transfer needs Face ID" |
| Too many wrong PINs/OTPs lock; rate limits work | `AuthFlowIntegrationTest` "five wrong pins lock the device…", "otp locks after five wrong codes", "wrong password … locks the account", `PaymentFlowIntegrationTest` "five wrong PINs on a payment lock the device", "name inquiries are rate limited per customer" |
| Reused refresh token revokes the family | `AuthFlowIntegrationTest` "reusing a refresh token revokes the whole family" |
| Missing or wrong device signature is refused | `AuthFlowIntegrationTest` "login needs a signature from the bound device key", `PaymentFlowIntegrationTest` "wrong PIN, wrong signature…", `CardsIntegrationTest` "reporting a card lost needs the PIN…" |
| App refuses a server whose key is not pinned | `PinningTests` (iOS): SPKI hash format, only pinned keys incl. backup accepted *(new in M6)* |
| Logs, crash reports and caches hold no Restricted/Confidential data | `LogMaskingTest`: 10–19 digit numbers and JWTs masked in messages and stack traces *(new in M6)*; `CardsIntegrationTest` "full card details … are not cached and are never stored"; `AuthFlowIntegrationTest` "audit trail is hash-chained and never stores secrets"; iOS uses an ephemeral `URLSession` (no disk cache) and logs only method, path and status |
| Compromised phone (AUTH-11) | `DeviceIntegrityIntegrationTest`, `DeviceIntegrityUITests` *(new in M6)* |

## 2. Changes made in M6

| Area | Change | Requirement |
|---|---|---|
| Compromised device | App detects jailbreak (and a debugger on Release builds), warns at launch, does not start payments and sends `X-Device-Integrity: compromised`. Backend then refuses transfers, bill payments and card reveal with `DEVICE_COMPROMISED` and audits it; viewing, freezing a card and sign-out still work | AUTH-11, OWASP Mobile M7 |
| Offline | Network monitor; "Offline" badge with the time of the data shown; payments disabled; reload on reconnect. The dashboard keeps its data when a refresh fails (it used to drop it) | NFR-08 |
| Log masking | Backend console pattern masks long digit runs and JWTs everywhere, including third-party exception text | NFR-05 |
| Contrast | `fractionText`, `positive` and `negative` darkened to pass WCAG AA on every surface they are used on; `ThemeContrastTests` checks 15 text/background pairs | NFR-09 |
| Dynamic Type & VoiceOver | Card actions wrap instead of truncating; satang digits scale with Dynamic Type; range picker gets a 44 pt target and its own row at large sizes; balance read as "Total balance, ฿…"; Welcome scrolls at accessibility sizes; tab, payee and card-face text shrink to fit | NFR-09 |
| Accessibility audit | `AccessibilityUITests` runs Apple's audit (labels, hit regions, clipped text, Dynamic Type) on Welcome, Home, Payments, Cards and Profile at the Accessibility-L text size and attaches screenshots | NFR-09 |
| Performance budget | `PerformanceBudgetTest` measures p95 with a year of history | NFR-02 |

## 3. Accessibility (NFR-09)

- **Audit:** the first run found 37 issues; all real ones were fixed (see section 2).
- **Contrast is excluded from the automated audit** because it samples rendered pixels: thin Thonburi strokes and text scrolled under the translucent tab bar report failures for pairs that measure 4.7–18.9:1. Contrast is instead checked exactly by `ThemeContrastTests`; a new colour or pairing must be added there.
- **Manual (before release):** a VoiceOver pass through onboarding → transfer → slip, and a check at the largest accessibility size on a small phone (iPhone SE).

## 4. Performance (NFR-01, NFR-02)

Measured in-process (MockMvc → PostgreSQL 16 + Redis in Testcontainers, Apple Silicon), p95 after warm-up, with 1,460 postings on the account:

| Call | p95 | Budget |
|---|---|---|
| `GET /dashboard` | 263 ms | 500 ms |
| `GET /accounts/{id}/transactions` | 9 ms | 500 ms |
| Transfer (inquiry + confirm, PIN) | 217 ms | 2 s |

- The dashboard is the slowest call: its balance history joins postings to journal entries by date, and `journal_entries` has no index on `occurred_at`. That is fine at simulation scale. At real-bank volumes, add `occurred_at` to `postings` (or a daily balance snapshot) before M7.
- Network latency is not included; the production SLO (NFR-02, NFR-03) is measured at the edge once hosting exists (M7).
- **NFR-01 (cold start ≤ 2 s, dashboard ≤ 1.5 s after unlock)** has to be measured on a physical iPhone 12 or later with Instruments (*manual*); simulator timings under parallel test load are not representative.

## 5. UAT checklist (*manual*, demo customer, Thai and English)

| # | Flow | Expected |
|---|---|---|
| 1 | Register with `1-2345-67890-12-1` / `LuxeDemo#2026`, OTP `000000`, set a PIN, enable Face ID | Lands on Home with name, balance and history |
| 2 | Lock (background 5 min), unlock with Face ID and with PIN | Balance hidden in App Switcher; unlock works both ways |
| 3 | History: filter, search, open a transaction, change its category | Insight on Home updates |
| 4 | Transfer to own savings, to `222-3-33444-5`, to PromptPay `0812345678` | Slip with QR; history and inbox show the movement |
| 5 | Transfer ฿50,000 | Face ID required |
| 6 | Other bank number ending `9999` | Rejected, nothing deducted |
| 7 | Pay the saved MEA bill; top up AIS ฿100 | Slip; bill marked paid |
| 8 | Scan a PromptPay QR from Photos | Recipient and amount filled |
| 9 | Cards: freeze/unfreeze, overseas on, daily limit, show number (Face ID), report lost (PIN) | Security alerts in the inbox; replacement card keeps points |
| 10 | Profile: change PIN, turn Face ID off/on, switch language, turn off transaction alerts | Language applies after relaunch; alerts stop pushing but still reach the inbox |
| 11 | Airplane mode | "Offline" badge, last data shown, payments refused; back online reloads |
| 12 | Sign out | Back to Welcome; old session cannot be used |

## 6. Remaining risks

- Jailbreak detection is best effort and can be hidden; the backend never treats its absence as proof of a safe phone (threat model I4).
- An access token stays valid up to 15 minutes after sign-out (threat model section 6).
- NFR-01 and the VoiceOver pass are manual until a device lab exists.
- Everything listed in [integration-guide.md](integration-guide.md) section 2 ("What a real gateway additionally needs") remains for a real system.
