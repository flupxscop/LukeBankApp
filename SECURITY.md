# Security policy

LuxeBank is a **simulation**: it holds no real customer data or money, and every external system is a stub.
Its security controls are still meant to be real, so reports are welcome.

## Reporting a vulnerability

Please report privately through **GitHub → Security → Report a vulnerability** on this repository
(private vulnerability reporting). Do not open a public issue for a security problem.

Include what you found, how to reproduce it and the impact you expect.

## Scope

- The iOS app (`ios/`), the API (`backend/`) and the API contract (`api/`)
- Bypassing device binding, PIN/Face ID step-up, ledger integrity, ownership checks (BOLA) or log masking

Out of scope: the stub adapters' simulated behaviour, findings that need a jailbroken or physically compromised
device beyond what the [threat model](docs/security/threat-model.md) covers, and denial of service.

## How the project protects itself

The [threat model](docs/security/threat-model.md) lists every threat and its mitigation, and the
[hardening report](docs/hardening-report.md) maps each required security test to the test that covers it.
Every pull request runs gitleaks, Semgrep, Trivy and CodeQL.
