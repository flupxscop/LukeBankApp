# LuxeBank

Premium iOS banking app (SwiftUI) with a Spring Boot + Kotlin backend.

- Specification: [docs/SPEC.md](docs/SPEC.md)
- Threat model: [docs/security/threat-model.md](docs/security/threat-model.md)
- API contract: [api/openapi.yaml](api/openapi.yaml)
- Simulation scope and how to connect real systems later: [docs/integration-guide.md](docs/integration-guide.md)

## Screenshots
<p align="center">
  <img src="assets/Sample_UI.png" width="450"/>
</p>

## Repository layout

```
ios/            SwiftUI app (XcodeGen project in ios/project.yml)
backend/        Spring Boot 4 + Kotlin, PostgreSQL, Redis, Flyway
api/            OpenAPI contract shared by iOS and backend
docs/           Specification and security documents
docker-compose.yml  Local stack: postgres + redis + backend
```

## Requirements

- Xcode with an iOS 17+ simulator
- `brew install xcodegen swiftlint openjdk@21 colima docker docker-compose`

## iOS

```bash
cd ios
xcodegen generate
open LuxeBank.xcodeproj
```

Release builds need the backend and its certificate pins as build settings, or the app refuses to start:
`LUXEBANK_API_BASE_URL=https://…` and `LUXEBANK_API_PINS=<base64 SPKI SHA-256>,<backup pin>`. Mock data and `-LuxeBankAPI` exist in Debug builds only.

Run the `LuxeBank` scheme on an iPhone simulator. By default the app uses mock repositories. To use the local backend, add the launch argument `-LuxeBankAPI http://127.0.0.1:8080` (Debug builds allow `localhost` only).

Demo customer (synthetic, local profile only): national ID `1-2345-67890-12-1`, password `LuxeDemo#2026`, OTP `000000`. On first start the `local` profile also seeds two accounts, budgets, a savings goal and a year of deterministic ledger history for the home and history screens.

Payments (M3) run against stub gateways in every profile except `prod` (which refuses to start with stubs):

- Other-bank and PromptPay numbers ending in `0000` do not exist; numbers ending in `9999` are rejected by the receiving bank (nothing is deducted).
- A second LuxeBank customer, account `222-3-33444-5`, receives internal transfers; the demo customer also has three favourite payees and saved bills (MEA `0123456789`, LuxeBank card).
- Bill references of all zeros are unknown; top-ups (AIS, TrueMove H, TrueMoney) take any amount.
- Amounts from ฿50,000 need Face ID, so test those on a device or a simulator with enrolled Face ID.

Cards (M4) use a simulated card processor: the demo customer has a debit card on the main account and a Titanium Reserve credit card (฿500,000 limit, purchases, points, travel insurance). Full card numbers are test numbers derived from the processor token and are never stored; revealing them needs Face ID.

Profile and notifications (M5): the profile tab shows the relationship manager (call, or a simulated chat), settings for PIN, Face ID, language (applies on the next launch) and notification preferences, registered devices and sign-out. Every money movement and security event lands in the in-app inbox (bell on the home screen); the backend's push adapter only logs. To see a banner on the simulator, drag a file from `ios/PushSamples` onto it, or run `xcrun simctl push booted com.luxebank.app ios/PushSamples/money-in.apns`.

Hardening (M6): a jailbroken phone (or `-SimulateCompromisedDevice` in Debug) is warned and cannot pay; with no connection (or `-SimulateOffline`) the app shows the last data with an "Offline" badge. Security-test traceability, accessibility and performance results and the UAT checklist are in [docs/hardening-report.md](docs/hardening-report.md).

App quality metrics (stability, speed, resource use) and how to re-measure them: [docs/app-quality-metrics.md](docs/app-quality-metrics.md), `scripts/measure-app.sh`.

Tests (unit + UI onboarding flow):

```bash
xcodebuild test -project ios/LuxeBank.xcodeproj -scheme LuxeBank -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Run the UI flow against the real backend:

```bash
TEST_RUNNER_LUXEBANK_API=http://127.0.0.1:8080 xcodebuild test -project ios/LuxeBank.xcodeproj -scheme LuxeBank -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:LuxeBankUITests
```

## Backend

Start Docker (Colima):

```bash
colima start
```

Run the whole stack. Secrets come from `.env`, which git ignores; copy the example and set your own `DB_PASSWORD` first:

```bash
cp .env.example .env
```

```bash
docker compose up -d --build
```

Running the backend outside Docker (`./gradlew bootRun --args='--spring.profiles.active=local'`) needs the same variables exported, e.g. `set -a; source ../.env; set +a`.

Health check: `curl http://127.0.0.1:8080/actuator/health`

Build, lint (ktlint, detekt) and test (Testcontainers):

```bash
cd backend && ./gradlew build
```

With Colima, Testcontainers needs:

```bash
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
```

## CI

GitHub Actions run on every pull request: iOS tests + SwiftLint, backend build + tests + 70% coverage gate, and the security gates from spec 13.4.3 (gitleaks, Semgrep, Trivy, CodeQL).
