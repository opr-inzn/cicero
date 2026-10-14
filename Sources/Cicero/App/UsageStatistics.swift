import CryptoKit
import Foundation
import Security

/// Counting how many people use Cicero. Each time it opens, while Settings → General → Share usage
/// statistics is on (it is at first), Cicero sends TelemetryDeck one signal: its version, the macOS version
/// and a hash of a random ID it keeps for this Mac, so each Mac counts once. Nothing about the user or their
/// fonts. Turned off, nothing is sent and the ID is forgotten, so turning it on again starts a new one.
enum UsageStatistics {
    static let defaultsKey = "usageStatistics.isOn"
    private static let idKey = "usageStatistics.id"
    /// Cicero's app in TelemetryDeck, from its dashboard. Nothing is sent while it's empty.
    private static let appID = ""

    /// Sends this launch's signal. Once, when the app has finished launching; a signal that fails isn't
    /// sent again.
    static func sendLaunch() {
        let defaults = UserDefaults.standard
        // A binary run from .build (swift run) has no version to send.
        guard defaults.object(forKey: defaultsKey) as? Bool ?? true,
              !appID.isEmpty, Bundle.main.bundleURL.pathExtension == "app",
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return }
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        // TelemetryDeck's own signal and parameter names, which its dashboard charts.
        let signal: [String: Any] = [
            "appID": appID,
            "clientUser": SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined(),
            "sessionID": UUID().uuidString,
            "type": "TelemetryDeck.Session.started",
            "isTestMode": isTestBuild,
            "payload": [
                "TelemetryDeck.AppInfo.version": version,
                "TelemetryDeck.AppInfo.buildNumber": build,
                "TelemetryDeck.Device.platform": "macOS",
                "TelemetryDeck.Device.systemVersion": "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                "TelemetryDeck.Device.systemMajorVersion": "macOS \(system.majorVersion)",
            ],
        ]
        var request = URLRequest(url: URL(string: "https://nom.telemetrydeck.com/v2/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [signal])
        // Ephemeral, so no cookies or cache are kept.
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request).resume()
        session.finishTasksAndInvalidate()
    }

    /// When the user turns the statistics off.
    static func forgetID() {
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    /// Whether this copy was built with build-app.sh, signed ad hoc and so without a team, unlike a release.
    /// TelemetryDeck keeps test signals apart from the others.
    private static var isTestBuild: Bool {
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
