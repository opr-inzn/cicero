import AppKit
import CiceroCore
import Observation

/// Keeps application sets' fonts on while their apps are open, and the fonts an app's documents asked for (see
/// `DocumentFontWatcher`) while that app is open. Follows which apps are running, and syncs when that, the sets, the
/// requests or the library change.
@Observable
final class AppSetWatcher {
    /// Bundle IDs of the apps running now.
    private(set) var running: Set<String> = []

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Files on for application sets after the last sync → the PostScript names of their faces.
    @ObservationIgnored private var managed: [String: Set<String>] = [:]
    /// PostScript names of fonts the user turned off, or on for good, while an app wanted them: left
    /// alone until no open app wants them, so the next time the app opens they come on again. Names,
    /// not paths: turning off a font from an app's folder moves its file.
    @ObservationIgnored private var dismissed: Set<String> = []
    /// Files that wouldn't turn on, with the apps that wanted them: tried again only once those change.
    @ObservationIgnored private var failed: [String: Set<String>] = [:]
    /// Bundle ID of an open app → the PostScript names of the fonts its documents use that it asked for.
    @ObservationIgnored private var requested: [String: Set<String>] = [:]
    /// Whether `requested` has been taken up again from the records since Cicero opened (see `restoreRequests`).
    @ObservationIgnored private var restoredRequests = false

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        running = Self.runningBundleIDs()
        // The list changes as an app starts launching, before it reads its fonts; the launch
        // notification comes only once it has finished.
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.runningAppsChanged() }
        }
        track()
    }

    func isRunning(_ app: LinkedApp) -> Bool {
        running.contains(app.bundleID)
    }

    /// Keeps these fonts on for the app until it quits, along with the ones it asked for before.
    func request(_ postScriptNames: Set<String>, for bundleID: String) {
        guard running.contains(bundleID), !postScriptNames.isSubset(of: requested[bundleID] ?? []) else { return }
        requested[bundleID, default: []].formUnion(postScriptNames)
        scheduleSync(after: .zero)
    }

    /// Lets go of the fonts apps' documents asked for: they turn off, unless a set wants them.
    func forgetRequests() {
        guard !requested.isEmpty else { return }
        requested = [:]
        scheduleSync(after: .zero)
    }

    // MARK: Changes

    private func runningAppsChanged() {
        let now = Self.runningBundleIDs()
        guard now != running, let model else { return }
        let changed = now.symmetricDifference(running)
        running = now
        let linked = Set(model.data.sets.flatMap(\.apps).map(\.bundleID)).union(requested.keys)
        requested = requested.filter { now.contains($0.key) }
        if !changed.isDisjoint(with: linked) { scheduleSync(after: .zero) }
    }

    /// Syncs after the sets, the records or the library change.
    private func track() {
        guard let model else { return }
        withObservationTracking {
            _ = model.data
            _ = model.library
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.track()
                self?.scheduleSync(after: .milliseconds(250))
            }
        }
    }

    private func scheduleSync(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.sync()
        }
    }

    // MARK: Syncing

    private func sync() {
        guard let model, model.hasScanned else { return }
        if !restoredRequests { restoreRequests() }
        let current = Self.onForAppSets(model.data.records)
        for (path, names) in managed where !current.contains(path) { dismissed.formUnion(names) }
        managed = managed.filter { current.contains($0.key) }
        // Ones on from before Cicero started, or before the library listed them.
        for path in current where managed[path]?.isEmpty ?? true { managed[path] = Set(names(in: path)) }
        let (wanted, faces) = plan()
        let records = model.data.records
        let turningOn = Set(wanted.keys.filter { records.temporary[$0] == nil && !(faces[$0]?.state.isActive ?? true) })
        let turningOff = current.filter { wanted[$0] == nil }
        let appsChanged = current.contains { path in
            wanted[path].map { Set(records.temporary[path]?.apps ?? []) != $0 } ?? false
        }
        guard !turningOn.isEmpty || !turningOff.isEmpty || appsChanged else { return }

        // The switches move at once, as for the user's own activations, and settle with the scan after.
        var operations: [Int] = []
        let on = self.faces(inFiles: turningOn)
        if !on.isEmpty { operations.append(model.expect(on, at: .on)) }
        let off = Dictionary(grouping: self.faces(inFiles: turningOff)) { face in
            // A font from an app's folder goes back to being on in that app.
            face.app != nil && records.appFolderOrigins[face.face.path] == nil ? SwitchPosition.app : .off
        }
        for (position, faces) in off { operations.append(model.expect(faces, at: position)) }

        model.enqueue { [weak self] model in
            // Worked out again: an operation that ran in the meantime may have changed what's on.
            guard let self else { return }
            let (wanted, faces) = self.plan()
            let result = await model.engine.syncAppSets(wanted, faces: faces, records: model.data.records)
            model.data.records = result.records
            self.managed = Dictionary(uniqueKeysWithValues: Self.onForAppSets(result.records).map { path in
                (path, self.managed[path] ?? Set(self.names(in: path)))
            })
            for path in result.failed { self.failed[path] = wanted[path] }
            if !result.failed.isEmpty {
                model.showToast(result.message)
            } else if result.succeeded > 0 {
                model.showToast("Activated fonts for \(self.appNames(wanting: wanted))")
            }
            // The engine has waited for macOS, so a scan now sees what the sync did.
            let scan = model.rescan()
            for operation in operations { model.settle(operation, after: scan) }
        }
    }

    /// The fonts open apps' documents asked for before Cicero last quit, from the records, which keep the apps that
    /// wanted each file. Otherwise they'd go off until the app is next in front and asked, and an app in the background
    /// would find the fonts of its open documents gone. A style an application set of the app has is the set's.
    private func restoreRequests() {
        restoredRequests = true
        guard let model, model.data.activatesDocumentFonts else { return }
        let session = ActivationEngine.currentSession()
        var apps: [String: Set<String>] = [:]
        for (path, record) in model.data.records.temporary where record.scope == .whileAppsRun && record.session == session {
            let open = Set(record.apps ?? []).intersection(running).intersection(DocumentFontWatcher.bundleIDs)
            if !open.isEmpty { apps[path] = open }
        }
        guard !apps.isEmpty else { return }
        for family in model.library.families {
            for face in family.faces {
                for app in apps[face.face.path] ?? [] {
                    let inSet = model.data.sets.contains { set in
                        set.apps.contains { $0.bundleID == app } && set.contains(style: face.face.postScriptName, of: family.id)
                    }
                    if !inSet { requested[app, default: []].insert(face.face.postScriptName) }
                }
            }
        }
    }

    /// Each file the open apps' sets have, or their documents asked for → those apps, and its face. Leaves out fonts
    /// Cicero can't turn on or off, the ones the user dismissed, and ones that failed for the same apps before.
    private func plan() -> (wanted: [String: Set<String>], faces: [String: LibraryFace]) {
        guard let model else { return ([:], [:]) }
        var wanted: [String: Set<String>] = [:]
        var faces: [String: LibraryFace] = [:]
        var wantedNames = Set<String>()
        func want(_ face: LibraryFace, for apps: Set<String>) {
            guard !ActivationEngine.isProtected(face.face.path) else { return }
            wantedNames.insert(face.face.postScriptName)
            guard !dismissed.contains(face.face.postScriptName) else { return }
            wanted[face.face.path, default: []].formUnion(apps)
            faces[face.face.path] = face
        }
        for set in model.data.sets where !set.apps.isEmpty {
            let apps = Set(set.apps.map(\.bundleID)).intersection(running)
            guard !apps.isEmpty else { continue }
            for name in set.memberFamilies {
                guard let family = model.library.family(name) else { continue }
                // Only the styles it has of a family it has some of.
                for face in family.faces where set.contains(style: face.face.postScriptName, of: name) { want(face, for: apps) }
            }
        }
        if !requested.isEmpty {
            for face in model.library.families.lazy.flatMap(\.faces) {
                let apps = Set(requested.filter { $0.value.contains(face.face.postScriptName) }.keys).intersection(running)
                if !apps.isEmpty { want(face, for: apps) }
            }
        }
        dismissed.formIntersection(wantedNames)
        failed = failed.filter { wanted[$0.key] == $0.value }
        for path in failed.keys { wanted[path] = nil }
        return (wanted, faces)
    }

    /// The library's faces in these files.
    private func faces(inFiles paths: Set<String>) -> [LibraryFace] {
        guard let model, !paths.isEmpty else { return [] }
        return model.library.families.flatMap(\.faces).filter { paths.contains($0.face.path) }
    }

    /// PostScript names of the library's faces in a file.
    private func names(in path: String) -> [String] {
        guard let model else { return [] }
        return model.library.families.lazy.flatMap(\.faces).filter { $0.face.path == path }.map(\.face.postScriptName)
    }

    private func appNames(wanting wanted: [String: Set<String>]) -> String {
        let ids = wanted.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        var seen = Set<String>()
        var names = (model?.data.sets ?? []).flatMap(\.apps).filter { ids.contains($0.bundleID) && seen.insert($0.bundleID).inserted }.map(\.name)
        // Apps that asked for their documents' fonts without being in a set.
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, ids.contains(id), seen.insert(id).inserted else { continue }
            names.append(app.localizedName ?? id)
        }
        return names.formatted(.list(type: .and))
    }

    private static func onForAppSets(_ records: ActivationRecords) -> Set<String> {
        Set(records.temporary.filter { $0.value.scope == .whileAppsRun }.keys)
    }

    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
