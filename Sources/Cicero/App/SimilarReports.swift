import CiceroCore
import CryptoKit
import Foundation

/// Sending the user's not-similar reports (see `SimilarReport`) to Cicero's website, which keeps them to improve similar
/// fonts, while Settings → General → Send not-similar reports is on (it is at first). Each report once; one that fails
/// isn't sent again. With it, a hash of a random ID Cicero keeps for this Mac, so that each Mac's reports count as one
/// person's. Turned off, nothing is sent and the ID is forgotten, so turning it on again starts a new one.
enum SimilarReports {
    static let defaultsKey = "similarReports.isOn"
    private static let idKey = "similarReports.id"
    private nonisolated static let url = URL(string: "https://cicero.maximilianinzinger.com/api/similar-reports")!

    /// A report of these families from this list, ready to send; nil while sending is off, and from a binary run from
    /// .build (swift run), which has no version to send.
    static func report(family: SimilarReport.Entry, notSimilar: [String], list: [SimilarReport.Entry],
                       shownIn: SimilarReport.Place) -> SimilarReport? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) as? Bool ?? true, Bundle.main.bundleURL.pathExtension == "app",
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return SimilarReport(app: version, build: build, macOS: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                             mac: SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined(),
                             test: false, shownIn: shownIn, family: family, notSimilar: notSimilar, list: list)
    }

    static func send(_ report: SimilarReport) {
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

    /// When the user turns the reports off.
    static func forgetID() {
        UserDefaults.standard.removeObject(forKey: idKey)
    }
}
