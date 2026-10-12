# Contributing

Thanks for your interest in LuxeBank. This is how changes are made here.

## Workflow

1. Branch from `main`; one topic per branch.
2. Keep the app and the API consistent with the [specification](docs/SPEC.md) and the
   [API contract](api/openapi.yaml); update both when behaviour changes.
3. Open a pull request using the template, including its security checklist.
4. CI must be green before merging: SwiftLint (strict), iOS unit and UI tests, backend build with ktlint, detekt,
   tests and the 70 % coverage gate, and the security gates.

## Before you push

```bash
# iOS
cd ios && xcodegen generate && swiftlint --strict
xcodebuild test -project LuxeBank.xcodeproj -scheme LuxeBank -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Backend
cd backend && ./gradlew ktlintFormat build
```

## Ground rules

- **Money moves only through `LedgerService`.** Never update balances directly.
- **Every endpoint checks ownership** and answers `404` for other customers' resources, with a test.
- **No secrets, personal data, card numbers or tokens** in code, logs or test fixtures. Local secrets live in `.env`.
- **Every user-facing string** goes in `Localizable.xcstrings`, in Thai and English.
- **External systems stay behind ports** (`integration/Ports.kt` on the server, repository protocols in the app).
- Match the surrounding code's style; formatters and linters decide formatting.

## Commit messages

Imperative subject under 72 characters, then a body explaining what and why.
