## What & why

<!-- Requirement IDs (e.g. TRF-05) and a short summary -->

## Security checklist (spec 13.4.1)

- [ ] Touches money, personal data or authentication → threat model attached or updated (`docs/security/threat-model.md`)
- [ ] Every new endpoint checks resource ownership and has a BOLA test (401/404 for other users)
- [ ] Input validated at the boundary; amounts use `Decimal` / `BigDecimal`
- [ ] No secrets, PII, card data or tokens in code, logs, crash reports or analytics
- [ ] Data stored per classification (spec 13.3.1)
- [ ] New dependency justified below (or none added)
- [ ] Auth / ledger / crypto changes have a second reviewer

## Testing

<!-- What was run: unit, integration, simulator, manual -->
