import Foundation
import MetricKit
import OSLog

/// What the app reports about its own health. Holds counts and durations only: no customer data.
struct AppHealthReport: Codable, Equatable {
    var periodStart: Date?
    var periodEnd: Date?
    var appVersion: String?
    // Stability
    var crashes = 0
    var hangs = 0
    var abnormalExits = 0
    var normalExits = 0
    var memoryLimitExits = 0
    var watchdogExits = 0
    // Speed
    var medianLaunchMilliseconds: Double?
    var medianResumeMilliseconds: Double?
    var medianHangMilliseconds: Double?
    var scrollHitchRatio: Double?
    // Resources
    var peakMemoryMegabytes: Double?
    var cpuSeconds: Double?
    var diskWritesMegabytes: Double?
    var cellularMegabytes: Double?
    var wifiMegabytes: Double?

    /// Share of exits that were not crashes or kills (the "crash-free sessions" figure).
    var crashFreeRate: Double? {
        let total = abnormalExits + normalExits
        return total == 0 ? nil : Double(normalExits) / Double(total)
    }
}

/// Where health reports go. The simulation only logs them; a real system forwards them to its
/// observability backend (see docs/integration-guide.md).
protocol TelemetrySink {
    func record(_ report: AppHealthReport)
}

struct LogTelemetrySink: TelemetrySink {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Telemetry")

    func record(_ report: AppHealthReport) {
        guard let data = try? JSONEncoder().encode(report), let json = String(data: data, encoding: .utf8) else { return }
        logger.notice("App health \(json, privacy: .public)")
    }
}

/// Receives MetricKit's daily metrics and crash/hang diagnostics from iOS (real devices only; the
/// simulator never delivers them) and turns them into `AppHealthReport`s.
final class AppMetricsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = AppMetricsCollector(sink: LogTelemetrySink())
    private let sink: TelemetrySink

    init(sink: TelemetrySink) {
        self.sink = sink
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        payloads.map(Self.report(from:)).forEach(sink.record)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            var report = AppHealthReport(periodStart: payload.timeStampBegin, periodEnd: payload.timeStampEnd)
            report.crashes = payload.crashDiagnostics?.count ?? 0
            report.hangs = payload.hangDiagnostics?.count ?? 0
            sink.record(report)
        }
    }

    static func report(from payload: MXMetricPayload) -> AppHealthReport {
        var report = AppHealthReport(
            periodStart: payload.timeStampBegin, periodEnd: payload.timeStampEnd, appVersion: payload.metaData?.applicationBuildVersion
        )
        if let exits = payload.applicationExitMetrics {
            let foreground = exits.foregroundExitData
            let background = exits.backgroundExitData
            report.normalExits = foreground.cumulativeNormalAppExitCount + background.cumulativeNormalAppExitCount
            report.memoryLimitExits = foreground.cumulativeMemoryResourceLimitExitCount + background.cumulativeMemoryResourceLimitExitCount
            report.watchdogExits = foreground.cumulativeAppWatchdogExitCount + background.cumulativeAppWatchdogExitCount
            report.abnormalExits = foreground.cumulativeAbnormalExitCount + background.cumulativeAbnormalExitCount
                + report.memoryLimitExits + report.watchdogExits
        }
        report.medianLaunchMilliseconds = payload.applicationLaunchMetrics.flatMap { median($0.histogrammedTimeToFirstDraw) }
        report.medianResumeMilliseconds = payload.applicationLaunchMetrics.flatMap { median($0.histogrammedApplicationResumeTime) }
        report.medianHangMilliseconds = payload.applicationResponsivenessMetrics.flatMap { median($0.histogrammedApplicationHangTime) }
        // Milliseconds of hitches per second of scrolling.
        report.scrollHitchRatio = payload.animationMetrics?.scrollHitchTimeRatio.value
        report.peakMemoryMegabytes = payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value
        report.cpuSeconds = payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value
        report.diskWritesMegabytes = payload.diskIOMetrics?.cumulativeLogicalWrites.converted(to: .megabytes).value
        report.cellularMegabytes = payload.networkTransferMetrics.map {
            ($0.cumulativeCellularUpload + $0.cumulativeCellularDownload).converted(to: .megabytes).value
        }
        report.wifiMegabytes = payload.networkTransferMetrics.map {
            ($0.cumulativeWifiUpload + $0.cumulativeWifiDownload).converted(to: .megabytes).value
        }
        return report
    }

    /// Median of a duration histogram, in milliseconds.
    private static func median(_ histogram: MXHistogram<UnitDuration>) -> Double? {
        let buckets = histogram.bucketEnumerator.compactMap { $0 as? MXHistogramBucket<UnitDuration> }
        let total = buckets.reduce(0) { $0 + $1.bucketCount }
        guard total > 0 else { return nil }
        var seen = 0
        for bucket in buckets {
            seen += bucket.bucketCount
            if seen * 2 >= total {
                let middle = (bucket.bucketStart.converted(to: .milliseconds).value + bucket.bucketEnd.converted(to: .milliseconds).value) / 2
                return middle
            }
        }
        return nil
    }
}
