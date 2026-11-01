import CryptoKit
import Foundation
import Security

/// Switching to a version with an older build, the latest of the track the user moved to, which Sparkle won't do: its
/// installer refuses any build older than the one running. The checks are Sparkle's: the DMG's EdDSA signature against SUPublicEDKey, and the app in it signed
/// by the same team as this one (or validly signed at all, for a build signed ad hoc). The new app is copied next to this
/// one first, so the swap after quitting is two renames in one folder.
enum VersionSwitch {
    enum Failure: LocalizedError {
        case cannotWrite(String), download, signature, mount, noApp, wrongApp, codeSignature, copy, helper

        var errorDescription: String? {
            switch self {
            case .cannotWrite(let folder): "Cicero can’t replace itself in \(folder)."
            case .download: "The download didn’t finish."
            case .signature: "The download isn’t signed with Cicero’s key."
            case .mount: "The download couldn’t be opened."
            case .noApp: "There’s no Cicero in the download."
            case .wrongApp: "The download has another version of Cicero than the update feed says."
            case .codeSignature: "The Cicero in the download isn’t signed by the same developer."
            case .copy: "Cicero couldn’t be copied next to this one."
            case .helper: "Cicero couldn’t start the step that replaces it after it quits."
            }
        }
    }

    /// Label of the launchd job that swaps the apps; launchd keeps it running after Cicero quits.
    static let helperLabel = "com.maximilianinzinger.Cicero.switch-version"

    /// Downloads `release`, checks it and copies its app next to this one, under a hidden name; returns that copy.
    static func stage(_ release: Updates.Release, step: @MainActor (String) -> Void) async throws -> URL {
        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: folder.path), fm.isWritableFile(atPath: current.path) else {
            throw Failure.cannotWrite(folder.path)
        }

        let work = fm.temporaryDirectory.appendingPathComponent("Cicero switching \(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let dmg = work.appendingPathComponent("Cicero.dmg")
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: release.url)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { throw Failure.download }
            try fm.moveItem(at: downloaded, to: dmg)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download
        }

        step("Checking Cicero \(release.version)…")
        try await Task.detached(priority: .userInitiated) { try verifySignature(of: dmg, signature: release.signature) }.value

        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        else { throw Failure.mount }
        // Detached before `work` goes, which the mount point is in.
        let staged: Result<URL, Error>
        do {
            staged = .success(try await stage(from: mount, release: release, next: current, step: step))
        } catch {
            staged = .failure(error)
        }
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        return try staged.get()
    }

    /// The checks of the app in the mounted DMG, and its copy next to `current`.
    private static func stage(from mount: URL, release: Updates.Release, next current: URL,
                              step: @MainActor (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        guard let app = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?.first(where: {
            $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }) else { throw Failure.noApp }
        guard Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String == release.build
        else { throw Failure.wrongApp }
        try await Task.detached(priority: .userInitiated) { try verifyCodeSignature(of: app, like: current) }.value

        step("Copying Cicero \(release.version)…")
        let staged = current.deletingLastPathComponent()
            .appendingPathComponent(".Cicero \(release.version) \(UUID().uuidString).app", isDirectory: true)
        guard await run("/usr/bin/ditto", [app.path, staged.path]) else {
            try? fm.removeItem(at: staged)
            throw Failure.copy
        }
        return staged
    }

    /// Starts a launchd job that waits for Cicero to quit, puts `staged` in its place, and opens it. If the rename fails,
    /// it puts this version back and opens that. The job removes itself; one run again finds nothing staged and stops.
    static func replaceAfterQuit(current: URL, with staged: URL) throws {
        let script = """
        pid="$1"; current="$2"; staged="$3"; label="$4"
        if [ -d "$staged" ]; then
            i=0
            while kill -0 "$pid" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
            old="$current.old-$$"
            if mv "$current" "$old"; then
                if mv "$staged" "$current"; then rm -rf "$old"; else mv "$old" "$current"; rm -rf "$staged"; fi
            else
                rm -rf "$staged"
            fi
            open "$current"
        fi
        launchctl remove "$label"
        """
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["remove", helperLabel]
        try? launchctl.run()
        launchctl.waitUntilExit()
        let submit = Process()
        submit.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        submit.arguments = ["submit", "-l", helperLabel, "--", "/bin/sh", "-c", script, "switch-version",
                            pid, current.path, staged.path, helperLabel]
        do { try submit.run() } catch { throw Failure.helper }
        submit.waitUntilExit()
        guard submit.terminationStatus == 0 else { throw Failure.helper }
    }

    /// Sparkle's check: an Ed25519 signature over the whole file, against the public key in Info.plist.
    nonisolated static func verifySignature(of file: URL, signature: String) throws {
        guard let keyText = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyData = Data(base64Encoded: keyText), let signatureData = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              key.isValidSignature(signatureData, for: data)
        else { throw Failure.signature }
    }

    /// A valid signature, nested code too, by the team that signed `current` when it has one.
    nonisolated static func verifyCodeSignature(of app: URL, like current: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw Failure.codeSignature }
        var requirement: SecRequirement?
        if let team = teamIdentifier(of: current) {
            guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString,
                                                 [], &requirement) == errSecSuccess else { throw Failure.codeSignature }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw Failure.codeSignature }
    }

    nonisolated private static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Runs a tool off the main thread; true when it succeeds.
    nonisolated private static func run(_ tool: String, _ arguments: [String]) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}
