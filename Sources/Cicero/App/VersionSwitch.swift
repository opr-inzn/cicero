import CryptoKit
import Foundation
import Security

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

    static let helperLabel = "com.maximilianinzinger.Cicero.switch-version"

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

        step("Checking Cicero \(release.version)")
        try await Task.detached(priority: .userInitiated) { try verifySignature(of: dmg, signature: release.signature) }.value

        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        else { throw Failure.mount }
        let staged: Result<URL, Error>
        do {
            staged = .success(try await stage(from: mount, release: release, next: current, step: step))
        } catch {
            staged = .failure(error)
        }
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        return try staged.get()
    }

    private static func stage(from mount: URL, release: Updates.Release, next current: URL,
                              step: @MainActor (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        guard let app = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?.first(where: {
            $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }) else { throw Failure.noApp }
        guard Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String == release.build
        else { throw Failure.wrongApp }
        try await Task.detached(priority: .userInitiated) { try verifyCodeSignature(of: app, like: current) }.value

        step("Copying Cicero \(release.version)")
        let staged = current.deletingLastPathComponent()
            .appendingPathComponent(".Cicero \(release.version) \(UUID().uuidString).app", isDirectory: true)
        guard await run("/usr/bin/ditto", [app.path, staged.path]) else {
            try? fm.removeItem(at: staged)
            throw Failure.copy
        }
        return staged
    }

    static func replaceAfterQuit(current: URL, with staged: URL) throws {
        let script = """
        pid="$1"; current="$2"; staged="$3"; label="$4"
        if [ -d "$staged" ]; then
            i=0
            while kill -0 "$pid" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
            if kill -0 "$pid" 2>/dev/null; then
                rm -rf "$staged"
            else
                old="$current.old-$$"
                if mv "$current" "$old"; then
                    if mv "$staged" "$current"; then rm -rf "$old"; else mv "$old" "$current"; rm -rf "$staged"; fi
                else
                    rm -rf "$staged"
                fi
                open "$current"
            fi
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

    // Must verify the Ed25519 signature over the whole DMG against SUPublicEDKey before mounting or copying.
    nonisolated static func verifySignature(of file: URL, signature: String) throws {
        guard let keyText = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyData = Data(base64Encoded: keyText), let signatureData = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              key.isValidSignature(signatureData, for: data)
        else { throw Failure.signature }
    }

    // Must verify nested code signatures and match the running app's team identifier before replacing the bundle.
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
