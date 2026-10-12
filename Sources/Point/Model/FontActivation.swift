import CoreText
import Foundation

/// Turning fonts on and off system-wide.
///
/// Activation either copies files into ~/Library/Fonts or registers them in place with CoreText.
/// Deactivation never deletes a user's only copy: copies Point made go to the Trash, other files in
/// ~/Library/Fonts are moved into Point's Deactivated folder (which stays in the library).
extension LibraryStore {
    func requestActivate(_ families: [FontFamily]) {
        requestActivate(faces: families.flatMap(\.faces), title: families.count == 1 ? families[0].name : "\(families.count) families")
    }

    func requestActivate(faces: [LibraryFace], title: String) {
        // Fonts on for this session only can be made permanent.
        var targets = faces.filter { $0.canActivate || $0.isTemporary }
        guard !targets.isEmpty else {
            showToast("Already on.")
            return
        }
        // Fonts an app already loads from its own folder (like Adobe's) are used where they are:
        // that folder stays put, and a copy would only show the app the same font twice.
        let appOnly = targets.filter { if case .appOnly = $0.status { true } else { false } }
        if !appOnly.isEmpty {
            Task { await activate(appOnly, method: .register) }
            targets.removeAll { if case .appOnly = $0.status { true } else { false } }
            guard !targets.isEmpty else { return }
        }
        switch data.installMethod {
        case .ask: pendingActivation = ActivationRequest(title: title, faces: targets)
        case .copy, .register: Task { await activate(targets, method: data.installMethod) }
        }
    }

    func activate(_ faces: [LibraryFace], method: InstallMethod) async {
        let paths = uniquePaths(of: faces)
        await endTemporaryActivation(of: paths)
        var failures: [String] = []
        switch method {
        case .copy, .ask:
            failures = copyToUserFonts(paths)
        case .register:
            let failed = await registerInPlace(paths)
            failures = failed
        }
        let succeeded = paths.count - failures.count
        if failures.isEmpty {
            showToast(succeeded == 1 ? "Activated." : "Activated \(succeeded) files.")
        } else {
            showToast("Couldn't activate \(failures.count) of \(paths.count) files.")
        }
        save()
        scheduleRescan(after: 0.8)
    }

    func requestDeactivate(_ families: [FontFamily]) {
        requestDeactivate(faces: families.flatMap(\.faces))
    }

    func requestDeactivate(faces: [LibraryFace]) {
        let targets = faces.filter(\.canDeactivate)
        guard !targets.isEmpty else {
            if faces.contains(where: { $0.status.isActive }) {
                showToast("These fonts are managed by macOS or another app.")
            } else {
                showToast("Nothing to deactivate.")
            }
            return
        }
        let unmanaged = targets.filter { $0.status == .active(.user) && !hasRestorableOriginal($0) }.map(\.face.path)
        let unmanagedCount = Set(unmanaged).count
        if unmanaged.isEmpty {
            Task { await deactivate(targets) }
        } else {
            pendingDeactivation = DeactivationRequest(faces: targets, unmanagedCount: unmanagedCount)
        }
    }

    func deactivate(_ faces: [LibraryFace]) async {
        let fm = FileManager.default
        var failures = 0
        var toUnregister: [String] = []
        var temporary: [String] = []
        for path in uniquePaths(of: faces) {
            let face = faces.first { $0.face.path == path }!
            switch face.status.activeKind {
            case .user:
                do {
                    if hasRestorableOriginal(face) {
                        try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    } else {
                        try fm.createDirectory(at: Persistence.deactivatedDirectory, withIntermediateDirectories: true)
                        let destination = uniqueDestination(Persistence.deactivatedDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent))
                        try fm.moveItem(at: URL(fileURLWithPath: path), to: destination)
                    }
                    data.installedCopies.removeValue(forKey: path)
                } catch {
                    NSLog("Point: deactivate \(path) failed: \(error)")
                    failures += 1
                }
            case .registered, .other:
                toUnregister.append(path)
            case .temporary:
                temporary.append(path)
            default:
                failures += 1
            }
        }
        if !toUnregister.isEmpty {
            failures += await unregister(toUnregister)
        }
        failures += await endTemporaryActivation(of: temporary)
        showToast(failures == 0 ? "Deactivated." : "Couldn't deactivate \(failures) files.")
        save()
        scheduleRescan(after: 0.8)
    }

    // MARK: Copy

    private func copyToUserFonts(_ paths: [String]) -> [String] {
        let fm = FileManager.default
        let userFonts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Fonts", isDirectory: true)
        try? fm.createDirectory(at: userFonts, withIntermediateDirectories: true)
        var failures: [String] = []
        for path in paths {
            let source = URL(fileURLWithPath: path)
            var destination = userFonts.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                if fileSize(destination.path) == fileSize(path) {
                    data.installedCopies[destination.path] = path
                    continue
                }
                destination = uniqueDestination(destination)
            }
            do {
                try fm.copyItem(at: source, to: destination)
                data.installedCopies[destination.path] = path
            } catch {
                NSLog("Point: copy \(path) failed: \(error)")
                failures.append(path)
            }
        }
        return failures
    }

    /// True when trashing this installed file still leaves another copy of the font outside ~/Library/Fonts,
    /// either the file Point copied it from or a matching file found in a watched folder.
    private func hasRestorableOriginal(_ face: LibraryFace) -> Bool {
        let fm = FileManager.default
        let userFonts = NSHomeDirectory() + "/Library/Fonts/"
        var candidates = face.otherPaths
        if let origin = data.installedCopies[face.face.path] { candidates.append(origin) }
        return candidates.contains { $0 != face.face.path && !$0.hasPrefix(userFonts) && fm.fileExists(atPath: $0) }
    }

    // MARK: Register in place

    private func registerInPlace(_ paths: [String]) async -> [String] {
        let failed = await CoreTextRegistration.register(paths.map { URL(fileURLWithPath: $0) })
        for path in paths where !failed.contains(path) { data.registeredPaths.insert(path) }
        return Array(failed)
    }

    private func unregister(_ paths: [String]) async -> Int {
        var failed = await CoreTextRegistration.unregister(paths.map { URL(fileURLWithPath: $0) }, scope: .persistent)
        if !failed.isEmpty {
            failed = await CoreTextRegistration.unregister(failed.map { URL(fileURLWithPath: $0) }, scope: .session)
        }
        for path in paths where !failed.contains(path) { data.registeredPaths.remove(path) }
        return failed.count
    }

    // MARK: Helpers

    private func uniquePaths(of faces: [LibraryFace]) -> [String] {
        var seen = Set<String>()
        return faces.map(\.face.path).filter { seen.insert($0).inserted }
    }

    private func fileSize(_ path: String) -> Int64? {
        FaceCache.stamp(of: path)?.size
    }

    private func uniqueDestination(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        for n in 2... {
            let candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}

enum CoreTextRegistration {
    /// Returns the paths that failed.
    static func register(_ urls: [URL], scope: CTFontManagerScope = .persistent) async -> Set<String> {
        await withCheckedContinuation { continuation in
            var failed = Set<String>()
            CTFontManagerRegisterFontURLs(urls as CFArray, scope, true) { errors, done in
                failed.formUnion(failedPaths(errors))
                if done { continuation.resume(returning: failed) }
                return true
            }
        }
    }

    static func unregister(_ urls: [URL], scope: CTFontManagerScope) async -> Set<String> {
        await withCheckedContinuation { continuation in
            var failed = Set<String>()
            CTFontManagerUnregisterFontURLs(urls as CFArray, scope) { errors, done in
                failed.formUnion(failedPaths(errors))
                if done { continuation.resume(returning: failed) }
                return true
            }
        }
    }

    private static func failedPaths(_ errors: CFArray) -> [String] {
        let list = errors as? [CFError] ?? []
        return list.flatMap { error -> [String] in
            let info = CFErrorCopyUserInfo(error) as? [String: Any]
            let urls = info?[kCTFontManagerErrorFontURLsKey as String] as? [URL] ?? []
            return urls.map(\.standardizedFileURL.path)
        }
    }
}
