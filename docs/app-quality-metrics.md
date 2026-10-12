# LuxeBank — App Quality Metrics

Stability, speed and resource use of the iOS app: what is measured, the target, how to measure it and the
latest result. Targets marked NFR come from the SPEC; the others are proposed here (marked *proposed*) from Apple's
guidance and common banking-app budgets, and can be adjusted.

| Field | Value |
|---|---|
| Measured | 2026-10-12, `scripts/measure-app.sh` on an iPhone 18 Pro simulator (iOS 27, Apple Silicon Mac) |
| Build | Debug with mock data unless stated; Release figures where marked |
| Caveat | The Mac was under load (load average 6–10 on 8 cores, three simulators, screen streaming). Simulator timings run on the Mac's CPU, so compare runs with each other and take release figures from a physical iPhone |

## How it is measured

| Tool | Where | What it gives |
|---|---|---|
| `AppMetricsUITests` (XCTest metrics) | `ios/LuxeBankUITests` | Launch time, signpost intervals, scroll metrics, memory, CPU, disk writes, a 30-round soak. Skipped unless `TEST_RUNNER_LUXEBANK_MEASURE=1` |
| Signposts | `Core/Telemetry/Signposts.swift` | `Startup`, `Unlock`, `DashboardLoad`, `HistoryLoad` intervals, visible in Instruments → Points of Interest |
| MetricKit | `Core/Telemetry/AppMetrics.swift` | On real devices, iOS delivers daily metrics and crash/hang diagnostics. `AppMetricsCollector` turns them into an `AppHealthReport` (counts and durations only) for a `TelemetrySink`; the simulation logs it |
| `PerformanceBudgetTest` | `backend/src/test/.../performance` | API p95 latency and response size |
| `scripts/measure-app.sh` | repo root | Runs all of the above for the app and reports the Release app size |

## 1. App stability

| Metric | Target | Result | Status |
|---|---|---|---|
| Crashes during automated use | 0 | 0 across 9 functional UI tests and a 30-round soak (≈ 150 screen visits plus 30 history pushes) | ✅ |
| Memory leak over repeated sessions | No upward trend | Change per iteration: +0.61, +0.08, −0.29, +0.07, +0.02 MB (no trend) | ✅ |
| Crash-free sessions (production) | ≥ 99.9 % *(proposed)* | Collected by MetricKit (`crashFreeRate`), needs real devices | 📡 device |
| Hangs > 250 ms (production) | 0 per day at p90 *(proposed)* | Collected by MetricKit (hang diagnostics, `medianHangMilliseconds`) | 📡 device |
| Memory-limit and watchdog terminations | 0 | Collected by MetricKit (`memoryLimitExits`, `watchdogExits`) | 📡 device |

## 2. Speed and responsiveness

| Metric | Target | Result | Status |
|---|---|---|---|
| App's own launch work (`Startup`: app created → first screen shown) | ≤ 400 ms on device *(proposed)* | 515 ms average (383–742 ms), Debug build on the loaded simulator; `AppEnvironment` set-up itself is 68 ms. Expect less on a device with a Release build | 📱 device |
| Cold launch to responsive (NFR-01) | ≤ 2.0 s on iPhone 12+ | Release 3.04 s, Debug 3.45–4.73 s on the simulator; Apple's Reminders measured 3.9–8.3 s in the same conditions, so the gap is simulator start-up | 📱 device |
| Unlock (`Unlock`: PIN → session) | ≤ 1.0 s on device *(proposed)* | 1.77 s average; 0.70 s of it is the mock's simulated network (2 × 350 ms), leaving ≈ 1.07 s for the simulator's software key and Debug code (devices use the Secure Enclave) | 📱 device |
| Dashboard data after unlock (`DashboardLoad`, NFR-01) | ≤ 1.5 s | 0.31 s average (0.24–0.44 s) | ✅ |
| Scroll hitch time ratio (history) | < 5 ms/s (Apple: "good") *(proposed)* | Not reported by the simulator; MetricKit `scrollHitchRatio` on devices. Scroll deceleration completes consistently (2.43 s ± 0.2 %) | 📱 device |
| API p95, reads (NFR-02) | ≤ 500 ms | dashboard 11–263 ms, history 5–9 ms (in-process, a year of history) | ✅ |
| API p95, transfer (NFR-02) | ≤ 2 s | 154–217 ms | ✅ |

## 3. Resource consumption

| Metric | Target | Result | Status |
|---|---|---|---|
| Peak memory, typical session (home → payments → cards → profile) | ≤ 150 MB *(proposed)* | 61.7 MB | ✅ |
| CPU time, typical session | ≤ 2 s per 6 s session *(proposed)* | 0.79 s over 5.9 s (≈ 13 % of one core) | ✅ |
| Disk writes per session | ≤ 1 MB *(proposed)* | 0 kB (no on-disk cache; Keychain only) | ✅ |
| Data per screen | dashboard ≤ 50 KB, history page ≤ 20 KB *(proposed)* | 18.5 KB and 4.9 KB, asserted in `PerformanceBudgetTest` | ✅ |
| App size (Release, arm64) | download ≤ 30 MB *(proposed)* | 18.0 MB bundle (executable 10.9 MB), ≈ 9.1 MB compressed | ✅ |
| Battery / energy | No "high" energy impact | Device only: Xcode Organizer and MetricKit CPU, display and network figures | 📱 device |

The app bundle's `Assets.car` is 7 MB, almost all of it the 1024 px app-icon images Xcode generates as a fallback for
iOS 17–18 (three appearances; the glow gradient compresses poorly). iOS 26 and later draws the icon from its vector
layers. If size matters later, simplify the glow or raise the deployment target.

**Status key:** ✅ measured and within target · 📱 needs a physical iPhone · 📡 needs production devices (MetricKit)

## Before release (manual)

1. Run `scripts/measure-app.sh "platform=iOS,name=<your iPhone>"` on an iPhone 12 or later with a Release build and fill the 📱 rows.
2. Profile launch with Instruments → App Launch; confirm cold launch ≤ 2 s.
3. In a real system, implement a `TelemetrySink` that sends `AppHealthReport` to the observability backend, then track crash-free sessions and hang rate per release (📡 rows).

## Re-running

```bash
scripts/measure-app.sh
```

Prints every metric with its average and spread, the pass/fail of each measurement test, and the Release app size.
