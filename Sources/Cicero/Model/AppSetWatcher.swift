import AppKit
import CiceroCore
import Observation

/// Keeps application sets' fonts on while their apps are open. Follows which apps are running, and
/// syncs when that, the sets or the library change.
@Observable
final class AppSetWatcher {
    /// Bundle IDs of the apps running now.
    private(set) var running: Set<String> = []

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Files on for application sets after the last sync.
    @ObservationIgnored private var managed: Set<String> = []
    /// Files the user turned off, or on for good, while an app wanted them: left alone until no open app
    /// wants them, so the next time the app opens they come on again.
    @ObservationIgnored private var dismissed: Set<String> = []
    /// Files that wouldn't turn on, with the apps that wanted them: tried again only once those change.
    @ObservationIgnored private var failed: [String: Set<String>] = [:]

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

    // MARK: Changes

    private func runningAppsChanged() {
        let now = Self.runningBundleIDs()
        guard now != running, let model else { return }
        let changed = now.symmetricDifference(running)
        running = now
        let linked = Set(model.data.sets.flatMap(\.apps).map(\.bundleID))
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
        let current = Self.onForAppSets(model.data.records)
        dismissed.formUnion(managed.subtracting(current))
        managed = current
        let (wanted, faces) = plan()
        let records = model.data.records
        let needsChange = current.contains { path in
            guard let apps = wanted[path] else { return true }
            return Set(records.temporary[path]?.apps ?? []) != apps
        } || wanted.contains { path, _ in
            records.temporary[path] == nil && !(faces[path]?.state.isActive ?? true)
        }
        guard needsChange else { return }

        model.enqueue { [weak self] model in
            // Worked out again: an operation that ran in the meantime may have changed what's on.
            guard let self else { return }
            let (wanted, faces) = self.plan()
            let result = await model.engine.syncAppSets(wanted, faces: faces, records: model.data.records)
            let changed = result.records != model.data.records
            model.data.records = result.records
            self.managed = Self.onForAppSets(result.records)
            for path in result.failed { self.failed[path] = wanted[path] }
            if !result.failed.isEmpty {
                model.showToast(result.message)
            } else if result.succeeded > 0 {
                model.showToast("Activated fonts for \(self.appNames(wanting: wanted)).")
            }
            if changed { model.scheduleRescan(after: 0.3) }
        }
    }

    /// Each file the open apps' sets have → those apps, and its face. Leaves out fonts Cicero can't
    /// turn on or off, the ones the user dismissed, and ones that failed for the same apps before.
    private func plan() -> (wanted: [String: Set<String>], faces: [String: LibraryFace]) {
        guard let model else { return ([:], [:]) }
        var wanted: [String: Set<String>] = [:]
        var faces: [String: LibraryFace] = [:]
        for set in model.data.sets where !set.apps.isEmpty {
            let apps = Set(set.apps.map(\.bundleID)).intersection(running)
            guard !apps.isEmpty else { continue }
            for name in set.families {
                guard let family = model.library.family(name) else { continue }
                for face in family.faces where !ActivationEngine.isProtected(face.face.path) {
                    wanted[face.face.path, default: []].formUnion(apps)
                    faces[face.face.path] = face
                }
            }
        }
        dismissed.formIntersection(wanted.keys)
        failed = failed.filter { wanted[$0.key] == $0.value }
        for path in dismissed.union(failed.keys) { wanted[path] = nil }
        return (wanted, faces)
    }

    private func appNames(wanting wanted: [String: Set<String>]) -> String {
        let ids = wanted.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        var seen = Set<String>()
        let names = (model?.data.sets ?? []).flatMap(\.apps).filter { ids.contains($0.bundleID) && seen.insert($0.bundleID).inserted }.map(\.name)
        return names.formatted(.list(type: .and))
    }

    private static func onForAppSets(_ records: ActivationRecords) -> Set<String> {
        Set(records.temporary.filter { $0.value.scope == .whileAppsRun }.keys)
    }

    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
