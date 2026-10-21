import CiceroCore
import CryptoKit
import Foundation

/// Sending the user's not-similar reports (see `SimilarReport`) to Cicero's website, which keeps them to improve similar
/// fonts, while Settings → General → Share usage statistics is on (it is at first; `UsageStatistics.isOn`). Without it, a
/// mark stays on the Mac, in the user's data. Each report once; one that fails isn't sent again. With it, a hash of a
/// random ID Cicero keeps for this Mac, its own rather than the usage statistics', so that each Mac's reports count as one
/// person's. Turning the statistics off forgets it, so turning them on again starts a new one. At most `dailyLimit` a
/// day, so that no one Mac uses up what the website may keep in a month.
enum SimilarReports {
    private static let idKey = "similarReports.id"
    /// The day reports were last sent ("2026-10-21", the Mac's own), and how many that day.
    private static let dayKey = "similarReports.day"
    private static let countKey = "similarReports.count"

    /// How many reports a day one Mac sends at most; the marks past it stay on the Mac, in the user's data.
    static let dailyLimit = 20
    private nonisolated static let url = URL(string: "https://cicero.maximilianinzinger.com/api/similar-reports")!

    /// A report of these families from this list, ready to send; nil while usage statistics are off, and from a binary
    /// run from .build (swift run), which has no version to send.
    static func report(family: SimilarReport.Entry, notSimilar: [String], list: [SimilarReport.Entry],
                       shownIn: SimilarReport.Place) -> SimilarReport? {
        let defaults = UserDefaults.standard
        guard UsageStatistics.isOn, Bundle.main.bundleURL.pathExtension == "app",
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return SimilarReport(app: version, build: build, macOS: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                             mac: SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined(),
                             test: false, shownIn: shownIn, family: family, notSimilar: notSimilar, list: list)
    }

    /// Sends the report, unless today's `dailyLimit` is used up.
    static func send(_ report: SimilarReport) {
        guard countToday() else { return }
        DispatchQueue.global(qos: .utility).async {
            var report = report
            report.test = UsageStatistics.isTestBuild
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(report)
            // Ephemeral, so no cookies or cache are kept.
            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: request).resume()
            session.finishTasksAndInvalidate()
        }
    }

    /// Counts a report as today's: false, counting nothing, when today's `dailyLimit` is used up.
    private static func countToday() -> Bool {
        let defaults = UserDefaults.standard
        let today = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: .withFullDate)
        let sent = defaults.string(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
        guard sent < dailyLimit else { return false }
        defaults.set(today, forKey: dayKey)
        defaults.set(sent + 1, forKey: countKey)
        return true
    }

    /// When the user turns usage statistics off.
    static func forgetID() {
        for key in [idKey, dayKey, countKey] { UserDefaults.standard.removeObject(forKey: key) }
    }
}
