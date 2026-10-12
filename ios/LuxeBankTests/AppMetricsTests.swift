import Foundation
import MetricKit
import Testing
@testable import LuxeBank

struct AppHealthReportTests {
    @Test func crashFreeRateCountsEveryAbnormalExit() {
        var report = AppHealthReport()
        #expect(report.crashFreeRate == nil)
        report.normalExits = 998
        report.abnormalExits = 2
        #expect(report.crashFreeRate == 0.998)
    }

    @Test func reportsCarryOnlyNumbers() throws {
        var report = AppHealthReport(appVersion: "1.0")
        report.crashes = 1
        report.peakMemoryMegabytes = 61.7
        let json = try #require(String(data: JSONEncoder().encode(report), encoding: .utf8))
        // Health data leaves the phone; it must never carry names, numbers or tokens (NFR-05).
        let allowed = Set(["periodStart", "periodEnd", "appVersion", "crashes", "hangs", "abnormalExits", "normalExits",
                           "memoryLimitExits", "watchdogExits", "medianLaunchMilliseconds", "medianResumeMilliseconds",
                           "medianHangMilliseconds", "scrollHitchRatio", "peakMemoryMegabytes", "cpuSeconds",
                           "diskWritesMegabytes", "cellularMegabytes", "wifiMegabytes"])
        let keys = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]).keys
        #expect(Set(keys).isSubset(of: allowed))
    }

    @Test func emptyDeliveriesRecordNothing() {
        final class Recording: TelemetrySink {
            var reports: [AppHealthReport] = []
            func record(_ report: AppHealthReport) { reports.append(report) }
        }
        let sink = Recording()
        // MetricKit payloads have no public initialiser, so only the delivery path is exercised here.
        AppMetricsCollector(sink: sink).didReceive([MXMetricPayload]())
        #expect(sink.reports.isEmpty)
    }
}
