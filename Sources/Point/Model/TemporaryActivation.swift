import AppKit
import CoreText
import Security

/// How long a session-only activation lasts. Point turns "until quit" fonts off itself; macOS drops
/// every session registration at logout.
enum TemporaryScope: String, Codable, CaseIterable, Hashable, Sendable {
    case untilQuit, untilLogout

    var menuLabel: String {
        switch self {
        case .untilQuit: "Until Point Quits"
        case .untilLogout: "Until You Log Out"
        }
    }

    var statusLabel: String {
        switch self {
        case .untilQuit: "Active until Point quits"
        case .untilLogout: "Active until you log out"
        }
    }

    var toastSuffix: String {
        switch self {
        case .untilQuit: "until Point quits"
        case .untilLogout: "until you log out"
        }
    }
}

/// A font file registered with CoreText in place, for the current login session only.
struct TemporaryActivation: Codable, Hashable, Sendable {
    var scope: TemporaryScope
    /// The login session it was registered in; a registration from another session is already gone.
    var session: String
}

/// Identifies the current login session: the security (audit) session ID, new on every login, paired
/// with the boot time because session IDs start over after a restart.
enum LoginSession {
    static let current: String = {
        var id: SecuritySessionId = 0
        var attributes = SessionAttributeBits(rawValue: 0)
        let status = SessionGetInfo(callerSecuritySession, &id, &attributes)
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return "\(boot.tv_sec)-\(status == errSecSuccess ? id : 0)"
    }()
}

extension LibraryStore {
    func requestActivateTemporarily(_ families: [FontFamily], scope: TemporaryScope) {
        requestActivateTemporarily(faces: families.flatMap(\.faces), scope: scope)
    }

    func requestActivateTemporarily(faces: [LibraryFace], scope: TemporaryScope) {
        let targets = faces.filter { $0.canActivate || ($0.isTemporary && $0.status != .active(.temporary(scope))) }
        guard !targets.isEmpty else {
            showToast("Already on.")
            return
        }
        Task { await activateTemporarily(targets, scope: scope) }
    }

    func activateTemporarily(_ faces: [LibraryFace], scope: TemporaryScope) async {
        var seen = Set<String>()
        let paths = faces.map(\.face.path).filter { seen.insert($0).inserted }
        // Files already on for the session only change when they turn off.
        let alreadyOn = Set(faces.filter(\.isTemporary).map(\.face.path))
        let toRegister = paths.filter { !alreadyOn.contains($0) }
        var failed = Set<String>()
        if !toRegister.isEmpty {
            failed = await CoreTextRegistration.register(toRegister.map { URL(fileURLWithPath: $0) }, scope: .session)
        }
        for path in paths where !failed.contains(path) {
            data.temporaryActivations[path] = TemporaryActivation(scope: scope, session: LoginSession.current)
        }
        let succeeded = paths.count - failed.count
        if failed.isEmpty {
            showToast(succeeded == 1 ? "Activated \(scope.toastSuffix)." : "Activated \(succeeded) files \(scope.toastSuffix).")
        } else {
            showToast("Couldn’t activate \(failed.count) of \(paths.count) files.")
        }
        save()
        scheduleRescan(after: 0.8)
    }

    /// Unregisters the session-only fonts among `paths` and forgets them, so the next scan shows their
    /// real state. Returns how many CoreText refused.
    @discardableResult
    func endTemporaryActivation(of paths: [String]) async -> Int {
        let targets = paths.filter { data.temporaryActivations[$0] != nil }
        guard !targets.isEmpty else { return 0 }
        let failed = await CoreTextRegistration.unregister(targets.map { URL(fileURLWithPath: $0) }, scope: .session)
        for path in targets { data.temporaryActivations.removeValue(forKey: path) }
        return failed.count
    }

    /// Called once at launch. Registrations from an earlier login session are gone already, so they are
    /// forgotten; "until quit" fonts still registered in this session were left behind by a crash and
    /// are turned off now. Normal quits turn them off from `willTerminateNotification`.
    func startTemporaryActivations() {
        let session = LoginSession.current
        var leftovers: [String] = []
        var keep: [String] = []
        for (path, entry) in data.temporaryActivations {
            if entry.session != session {
                data.temporaryActivations.removeValue(forKey: path)
            } else if entry.scope == .untilQuit {
                leftovers.append(path)
            } else {
                keep.append(path)
            }
        }
        if !leftovers.isEmpty {
            CoreTextRegistration.unregisterNow(leftovers.map { URL(fileURLWithPath: $0) }, scope: .session)
            for path in leftovers { data.temporaryActivations.removeValue(forKey: path) }
        }
        if !keep.isEmpty {
            let available = Set(((CTFontManagerCopyAvailableFontURLs() as? [URL]) ?? []).map { $0.standardizedFileURL.path })
            for path in keep where !available.contains(path) { data.temporaryActivations.removeValue(forKey: path) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endTemporaryActivationsForQuit() }
        }
    }

    private func endTemporaryActivationsForQuit() {
        let paths = data.temporaryActivations.filter { $0.value.scope == .untilQuit }.map(\.key)
        guard !paths.isEmpty else { return }
        CoreTextRegistration.unregisterNow(paths.map { URL(fileURLWithPath: $0) }, scope: .session)
        for path in paths { data.temporaryActivations.removeValue(forKey: path) }
        save()
    }
}

extension CoreTextRegistration {
    /// Synchronous, for the moment before the app exits.
    static func unregisterNow(_ urls: [URL], scope: CTFontManagerScope) {
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerUnregisterFontsForURL(url as CFURL, scope, &error) {
                NSLog("Point: unregister \(url.path) failed: \(error.map { String(describing: $0.takeRetainedValue()) } ?? "")")
            }
        }
    }
}
