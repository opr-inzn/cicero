import CryptoKit
import Foundation
import Security

enum UsageStatistics {
    static let defaultsKey = "usageStatistics.isOn"
    private static let idKey = "usageStatistics.id"
    private nonisolated static let newMacKey = "usageStatistics.countedAsNew"
    private nonisolated static let appID = "E1677081-90F9-4658-91F1-B9C63EFDAEAD"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func sendLaunch() {
        let defaults = UserDefaults.standard
        guard isOn, !appID.isEmpty, Bundle.main.bundleURL.pathExtension == "app",
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return }
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        let isNew = !defaults.bool(forKey: newMacKey)
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
        func signal(_ type: String, adding parameters: [String: String] = [:]) -> [String: Any] {
            ["appID": appID, "clientUser": clientUser, "sessionID": sessionID, "type": type, "isTestMode": isTestMode,
             "payload": payload.merging(parameters) { $1 }]
        }
        var signals = [signal("TelemetryDeck.Session.started")]
        if isNew {
            let today = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: .withFullDate)
            signals.insert(signal("TelemetryDeck.Acquisition.newInstallDetected",
                                  adding: ["TelemetryDeck.Acquisition.firstSessionDate": today]), at: 0)
        }
        var request = URLRequest(url: URL(string: "https://nom.telemetrydeck.com/v2/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: signals)
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { _, response, _ in
            guard isNew, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
            UserDefaults.standard.set(true, forKey: newMacKey)
        }.resume()
        session.finishTasksAndInvalidate()
    }

    static func forgetID() {
        UserDefaults.standard.removeObject(forKey: idKey)
    }

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
