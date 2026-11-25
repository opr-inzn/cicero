import AppKit
import CiceroCore
import Observation

@Observable
final class AppSetWatcher {
    private(set) var running: Set<String> = []

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var managed: [String: Set<String>] = [:]
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var failed: [String: Set<String>] = [:]
    @ObservationIgnored private var requested: [String: Set<String>] = [:]
    @ObservationIgnored private var restoredRequests = false
    @ObservationIgnored private var queued = false
    @ObservationIgnored private var syncsAgain = false

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        running = Self.runningBundleIDs()
        // The list changes as an app starts launching, before it reads its fonts. The launch notification comes only once it has finished.
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.runningAppsChanged() }
        }
        track()
    }

    func isRunning(_ app: LinkedApp) -> Bool {
        running.contains(app.bundleID)
    }

    func request(_ postScriptNames: Set<String>, for bundleID: String) {
        guard running.contains(bundleID), !postScriptNames.isSubset(of: requested[bundleID] ?? []) else { return }
        requested[bundleID, default: []].formUnion(postScriptNames)
        scheduleSync(after: .zero)
    }

    func allow(_ postScriptNames: Set<String>) {
        guard !postScriptNames.isDisjoint(with: dismissed) else { return }
        dismissed.subtract(postScriptNames)
        scheduleSync(after: .zero)
    }

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
        guard !queued else { return syncsAgain = true }
        if !restoredRequests { restoreRequests() }
        let current = Self.onForAppSets(model.data.records)
        for (path, names) in managed where !current.contains(path) { dismissed.formUnion(names) }
        managed = managed.filter { current.contains($0.key) }
        let missingManaged = current.filter { managed[$0]?.isEmpty ?? true }
        if !missingManaged.isEmpty {
            let namesByPath = Self.namesByPath(for: missingManaged, in: model.library)
            for path in missingManaged { managed[path] = namesByPath[path] ?? [] }
        }
        let (wanted, faces) = plan()
        let records = model.data.records
        let turningOn = Set(wanted.keys.filter { records.temporary[$0] == nil && !(faces[$0]?.state.isActive ?? true) })
        let turningOff = current.filter { wanted[$0] == nil }
        let appsChanged = current.contains { path in
            wanted[path].map { Set(records.temporary[path]?.apps ?? []) != $0 } ?? false
        }
        guard !turningOn.isEmpty || !turningOff.isEmpty || appsChanged else { return }

        var operations: [Int] = []
        let on = self.faces(inFiles: turningOn)
        if !on.isEmpty { operations.append(model.expect(on, at: .on)) }
        let off = Dictionary(grouping: self.faces(inFiles: turningOff)) { face in
            face.app != nil && records.appFolderOrigins[face.face.path] == nil ? SwitchPosition.app : .off
        }
        for (position, faces) in off { operations.append(model.expect(faces, at: position)) }

        queued = model.enqueue { [weak self] model in
            guard let self else { return }
            defer {
                self.queued = false
                if self.syncsAgain {
                    self.syncsAgain = false
                    self.scheduleSync(after: .zero)
                }
            }
            let (wanted, faces) = self.plan()
            let result = await model.engine.syncAppSets(wanted, faces: faces, records: model.data.records)
            model.data.records = result.records
            let activeForAppSets = Self.onForAppSets(result.records)
            let uncached = activeForAppSets.filter { self.managed[$0] == nil }
            let namesByPath = uncached.isEmpty ? [:] : Self.namesByPath(for: uncached, in: model.library)
            self.managed = Dictionary(uniqueKeysWithValues: activeForAppSets.map { path in
                (path, self.managed[path] ?? namesByPath[path] ?? [])
            })
            for path in result.failed { self.failed[path] = wanted[path] }
            if !result.failed.isEmpty {
                model.showToast(result.message)
            } else if result.succeeded > 0 {
                model.showToast("\(FontNames.describe(on) ?? "Fonts") activated for \(self.appNames(wanting: wanted))")
            }
            let scan = model.rescanFontd()
            for operation in operations { model.settle(operation, after: scan) }
        }
    }

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
        let appSets = model.data.sets.filter { !$0.apps.isEmpty }.map { (apps: Set($0.apps.map(\.bundleID)), lookup: $0.lookup()) }
        for family in model.library.families {
            for face in family.faces {
                for app in apps[face.face.path] ?? [] {
                    let inSet = appSets.contains { entry in
                        entry.apps.contains(app) && entry.lookup.contains(style: face.face.postScriptName, of: family.id)
                    }
                    if !inSet { requested[app, default: []].insert(face.face.postScriptName) }
                }
            }
        }
    }

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
            let lookup = set.lookup()
            for name in set.memberFamilies {
                guard let family = model.library.family(name) else { continue }
                for face in family.faces where lookup.contains(style: face.face.postScriptName, of: name) { want(face, for: apps) }
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

    private func faces(inFiles paths: Set<String>) -> [LibraryFace] {
        guard let model, !paths.isEmpty else { return [] }
        return model.library.families.flatMap(\.faces).filter { paths.contains($0.face.path) }
    }

    private static func namesByPath(for paths: Set<String>, in library: Library) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for face in library.families.lazy.flatMap(\.faces) where paths.contains(face.face.path) {
            result[face.face.path, default: []].insert(face.face.postScriptName)
        }
        return result
    }

    private func appNames(wanting wanted: [String: Set<String>]) -> String {
        let ids = wanted.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        var seen = Set<String>()
        var names = (model?.data.sets ?? []).flatMap(\.apps).filter { ids.contains($0.bundleID) && seen.insert($0.bundleID).inserted }.map(\.name)
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, ids.contains(id), seen.insert(id).inserted else { continue }
            names.append(app.localizedName ?? id)
        }
        return names.listed()
    }

    private static func onForAppSets(_ records: ActivationRecords) -> Set<String> {
        Set(records.temporary.filter { $0.value.scope == .whileAppsRun }.keys)
    }

    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
