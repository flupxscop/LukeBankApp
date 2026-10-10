# LuxeBank — Threat Model (baseline, M0)

STRIDE review of the system as designed in [SPEC.md](../SPEC.md). Update this file in the PR of every feature that touches money, personal data or authentication (spec 13.4.1).

| Field | Value |
|---|---|
| Version | 0.1 (M0 baseline) |
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
| S1 | Attacker logs in with a stolen password | Auth | OTP to registered phone, device binding, PIN/biometric unlock (AUTH-01…05) | Planned M1 |
| S2 | Stolen refresh token reused on another device | Auth | Rotation + reuse detection, token bound to device key (13.1 A07) | Planned M1 |
| S3 | Forged request from a non-registered device | API | Money requests signed by Secure Enclave key, verified server-side (13.1 A08) | Planned M3 |
| T1 | Amount or recipient changed between confirm and submit | Transfer | Server-side `inquiry_id` binds amount/recipient for 5 min; client values ignored (TRF-05) | Planned M3 |
| T2 | Ledger tampered with or left unbalanced | DB | Double-entry constraint, `SELECT … FOR UPDATE`, daily reconciliation (13.2) | Planned M2 |
| T3 | Audit trail altered to hide activity | DB | Append-only trigger + hash chain | **Done (V1 migration, tested)** |
| R1 | Customer disputes a transfer they made | Transfer | Audit log with actor, device, IP, trace ID; signed request stored (13.1 A09) | Planned M3 |
| I1 | Another customer's accounts read via ID guessing (BOLA) | API | UUID IDs, ownership check in service layer, BOLA test per endpoint (13.1 A01/API1) | Planned M2 |
| I2 | Sensitive data leaks through logs, errors or screenshots | All | No stack traces, shared error body, log masking, App Switcher overlay, screenshot block on card reveal | **Partly done** (error body, no stack traces) |
| I3 | Man-in-the-middle on hostile Wi-Fi | Network | ATS with no exceptions + certificate pinning (13.1 M5) | Planned M1 |
| I4 | Data extracted from a lost or jailbroken phone | Device | Keychain `WhenUnlockedThisDeviceOnly`, file protection complete, jailbreak detection (AUTH-11) | Planned M1 |
| D1 | Brute force or flooding of login/OTP/transfer endpoints | API | Bucket4j rate limits, lockout, request size limits, WAF (13.1 API4) | Partly done (request size limits) |
| D2 | Slow external provider takes the API down | Adapters | Timeouts, circuit breakers (Resilience4j), offline read-only app (NFR-08) | Planned M3 |
| E1 | Unauthenticated access to internal endpoints | API | Deny-by-default security chain; only `health` and API docs public | **Done (tested)** |
| E2 | Stub adapters accidentally deployed to production | Config | `prod` profile fails fast when a stub adapter is active (spec 7.0) | Planned M1 |

## 4. Abuse cases to test (spec 13.4.4)

Kept in sync with the security test list; each becomes an automated test when its feature lands.

## 5. Open risks

- Hosting region not chosen yet (D5) — affects PDPA cross-border transfer assessment.
- Production providers not contracted — adapter security reviewed again before M7.
