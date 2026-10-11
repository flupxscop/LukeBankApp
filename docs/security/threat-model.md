# LuxeBank — Threat Model

STRIDE review of the system as designed in [SPEC.md](../SPEC.md). Update this file in the PR of every feature that touches money, personal data or authentication (spec 13.4.1).

| Field | Value |
|---|---|
| Version | 0.6 (M4 cards) |
| Date | 2026-10-11 |
| Scope | iOS app, `/api/v1` backend, PostgreSQL, Redis, external adapters (stubs) |

## 1. Assets

| Asset | Classification (spec 13.3.1) |
|---|---|
| Account balances, ledger postings | Confidential, integrity-critical |
| Transfer and bill-payment requests | Integrity-critical |
| Credentials: password, PIN, OTP, tokens, device private key | Restricted |
| National ID, name, phone, account numbers | Confidential |
| Card data (PAN, CVV) | Restricted — never stored by LuxeBank |
| Audit log | Integrity-critical |

## 2. Trust boundaries

```
[iPhone: app + Keychain + Secure Enclave]
        │  TLS 1.2+ with public-key pinning, signed money requests
        ▼
[Edge: WAF / rate limit] ──▶ [Backend /api/v1] ──▶ [PostgreSQL]  (encrypted columns, append-only audit)
                                   │            └─▶ [Redis]       (rate limits, OTP, no PII)
                                   └──▶ [External adapters: SMS, ITMX/PromptPay, bills, card processor]
```

## 3. STRIDE

| # | Threat | Where | Mitigation (spec ref) | Status |
|---|---|---|---|---|
| S1 | Attacker logs in with a stolen password | Auth | OTP to registered phone, device binding, PIN/biometric unlock (AUTH-01…05) | **Done (M1, tested)** |
| S2 | Stolen refresh token reused on another device | Auth | Rotation + reuse detection, token bound to device key (13.1 A07) | **Done (M1, tested)** |
| S3 | Forged request from a non-registered device | API | Payment confirmations sign a single-use, inquiry-bound challenge with the Secure Enclave device key (+ PIN) or the Face ID key; inquiries are scoped to user + device (13.1 A08) | **Done (M3, tested incl. forged signature)** |
| T1 | Amount or recipient changed between confirm and submit | Transfer | Server-side inquiry fixes amount/recipient for 5 min; confirm accepts only the inquiry id; expired or reused inquiries rejected (TRF-05) | **Done (M3, tested)** |
| T2 | Ledger tampered with or left unbalanced | DB | Double-entry constraint trigger, append-only postings, non-negative customer balance check, `SELECT … FOR UPDATE` in id order, idempotency key, daily reconciliation job (13.2) | **Done (M2, tested incl. concurrent debits)** |
| T3 | Audit trail altered to hide activity | DB | Append-only trigger + hash chain | **Done (V1 migration, tested)** |
| R1 | Customer disputes a transfer they made | Transfer | PAYMENT_SUCCEEDED/FAILED and PAYMENT_AUTH_FAILED in the hash-chained audit log with device, IP, trace ID and method; slip with verification QR (13.1 A09) | **Done (M3)** — storing the signature itself is a follow-up |
| I1 | Another customer's accounts read via ID guessing (BOLA) | API | UUID IDs, every account/transaction query scoped by owner and answering 404, BOLA tests for list, detail and update (13.1 A01/API1) | **Done (M2, tested)** |
| I2 | Sensitive data leaks through logs, errors or screenshots | All | No stack traces, shared error body, log masking, App Switcher overlay, screenshot block on card reveal | **Partly done** (error body, App Switcher overlay, OTP never logged); card reveal in M4 |
| I5 | Release build ships mock data or an unpinned connection | iOS | Release refuses to start without an HTTPS base URL and SPKI pins; mocks and `-LuxeBankAPI` compile into Debug only (D22) | **Done (M3 review, tested)** |
| I6 | Card number or CVV leaked from storage, cache or screen | Cards | No PAN/CVV in LuxeBank's DB (processor token only); reveal needs a Face ID step-up and is audited; `Cache-Control: no-store`; app hides after 30 s, when backgrounded or screen-captured, and marks the fields privacy-sensitive | **Done (M4, tested)** — encrypting the reveal to a device key is a documented extension (D27) |
| S4 | Someone with an unlocked phone blocks or reveals a card | Cards | Report lost needs the PIN, reveal needs Face ID, both on a single-use device challenge; shared PIN lockout | **Done (M4, tested)** |
| I3 | Man-in-the-middle on hostile Wi-Fi | Network | ATS with no exceptions (Debug allows localhost only) + public-key pinning (13.1 M5) | **Built (M1); pins added when the production host exists** |
| I4 | Data extracted from a lost or jailbroken phone | Device | Keychain `WhenUnlockedThisDeviceOnly`, Secure Enclave keys, jailbreak signal (AUTH-11) | **Done (M1)**; jailbreak warning UI in M5 |
| D1 | Brute force or flooding of login/OTP/transfer endpoints | API | Redis rate limit per IP + endpoint, per-customer limit on payment name inquiries (enumeration, API6), password/OTP/PIN lockouts shared by login and payments, request size limits, WAF (13.1 API4) | **Done for auth (M1) and payments (M3)**; WAF at deploy |
| D3 | Connection-pool starvation under concurrent logins/payments | API/DB | No nested REQUIRES_NEW while a transaction holds a connection; audits join the caller; regression tests with more concurrent requests than pooled connections | **Done (M3 review, tested)** |
| D4 | One hot row (clearing account) serialises all external payments | DB | Internal accounts keep no balance snapshot and are not locked (D23) | **Done (M3 review)** |
| D2 | Slow external provider takes the API down | Adapters | Timeouts, circuit breakers (Resilience4j), offline read-only app (NFR-08) | Partly done — stub gateway rejections roll the debit back; timeouts, circuit breakers and pending/reversal for real gateways remain before M7 |
| E1 | Unauthenticated access to internal endpoints | API | Deny-by-default security chain; only `health` and API docs public | **Done (tested)** |
| E2 | Stub adapters accidentally deployed to production | Config | `prod` profile fails fast when a stub adapter is active (spec 7.0) | **Done (M1)** |

## 4. Abuse cases to test (spec 13.4.4)

Kept in sync with the security test list; each becomes an automated test when its feature lands.

## 5. Open risks

- Hosting region not chosen yet (D5) — affects PDPA cross-border transfer assessment.
- Production providers not contracted — adapter security reviewed again before M7.

## 6. Residual risks after M1

- An access token stays valid for up to 15 minutes after logout or device revocation. Acceptable for now; revisit with a token denylist if needed.
- In the simulator the device key is a software key in the Keychain (no Secure Enclave). Real devices always use the Secure Enclave.
- Rate limiting is per IP; customers behind carrier-grade NAT share a budget. Per-account lockouts still apply.
