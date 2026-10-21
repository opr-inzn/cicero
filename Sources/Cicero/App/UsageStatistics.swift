import CryptoKit
import Foundation
import Security

/// Counting how many people use Cicero. Each time it opens, while Settings → General → Share usage
/// statistics is on (it is at first), Cicero sends TelemetryDeck one signal: its version, the macOS version
/// and a hash of a random ID it keeps for this Mac, so each Mac counts once. The first time, a second signal
/// says the Mac is new, so the dashboard can count new users. Nothing about the user or their fonts. Turned
/// off, nothing is sent and the ID is forgotten, so turning it on again starts a new one.
enum UsageStatistics {
    static let defaultsKey = "usageStatistics.isOn"
    private static let idKey = "usageStatistics.id"
    /// Set once TelemetryDeck has had the signal saying this Mac is new. Kept when the statistics are turned
    /// off, so turning them on again doesn't count the Mac as new twice.
    private nonisolated static let newMacKey = "usageStatistics.countedAsNew"
    /// Cicero's app in TelemetryDeck, from its dashboard. Nothing is sent while it's empty.
    private nonisolated static let appID = "E1677081-90F9-4658-91F1-B9C63EFDAEAD"

    /// Whether Share usage statistics is on, as it is at first. Not-similar reports go with it (see `SimilarReports`).
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Sends this launch's signal. Once, when the app has finished launching; a signal that fails isn't
    /// sent again, except the one saying the Mac is new, which the next launch tries again.
    static func sendLaunch() {
        let defaults = UserDefaults.standard
        // A binary run from .build (swift run) has no version to send.
        guard isOn, !appID.isEmpty, Bundle.main.bundleURL.pathExtension == "app",
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return }
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        let isNew = !defaults.bool(forKey: newMacKey)
        // Reading the code signature takes milliseconds the window, still being made, needs more.
        DispatchQueue.global(qos: .utility).async { send(id: id, version: version, build: build, isNew: isNew) }
    }

    private nonisolated static func send(id: String, version: String, build: String, isNew: Bool) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let clientUser = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let sessionID = UUID().uuidString
        let isTestMode = isTestBuild
        let payload = [
            "TelemetryDeck.AppInfo.version": version,
            "TelemetryDeck.AppInfo.buildNumber": build,
            "TelemetryDeck.Device.platform": "macOS",
            "TelemetryDeck.Device.systemVersion": "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "macOS \(system.majorVersion)",
        ]
        // TelemetryDeck's own signal and parameter names, which its dashboard charts.
        func signal(_ type: String, adding parameters: [String: String] = [:]) -> [String: Any] {
            ["appID": appID, "clientUser": clientUser, "sessionID": sessionID, "type": type, "isTestMode": isTestMode,
             "payload": payload.merging(parameters) { $1 }]
        }
        var signals = [signal("TelemetryDeck.Session.started")]
        // Its Acquisition charts count new users by this signal, which its SDK sends on an app's first launch,
        // with that day.
        if isNew {
            let today = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: .withFullDate)
            signals.insert(signal("TelemetryDeck.Acquisition.newInstallDetected",
                                  adding: ["TelemetryDeck.Acquisition.firstSessionDate": today]), at: 0)
        }
        var request = URLRequest(url: URL(string: "https://nom.telemetrydeck.com/v2/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: signals)
        // Ephemeral, so no cookies or cache are kept.
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { _, response, _ in
            guard isNew, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
            UserDefaults.standard.set(true, forKey: newMacKey)
        }.resume()
        session.finishTasksAndInvalidate()
    }

    /// When the user turns the statistics off.
    static func forgetID() {
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    /// Whether this copy was built with build-app.sh, signed ad hoc and so without a team, unlike a release.
    /// TelemetryDeck keeps test signals apart from the others, and the website test reports (see `SimilarReports`).
    nonisolated static var isTestBuild: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return true }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] == nil
    }
}
