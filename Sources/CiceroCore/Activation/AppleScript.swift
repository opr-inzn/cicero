import Foundation

public enum AppleScript {
    // NSAppleScript and OSA aren't thread-safe, so run every script on one serial queue.
    private static let queue = DispatchQueue(label: "Cicero.AppleScript", qos: .userInitiated)

    public struct ErrorInfo: Sendable {
        public let number: Int?
        public let message: String
    }

    public static func run(_ source: String) async -> ErrorInfo? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: ErrorInfo(number: nil, message: ""))
                    return
                }
                var error: NSDictionary?
                _ = script.executeAndReturnError(&error)
                continuation.resume(returning: error.map {
                    ErrorInfo(number: $0[NSAppleScript.errorNumber] as? Int, message: $0[NSAppleScript.errorMessage] as? String ?? "")
                })
            }
        }
    }
}
