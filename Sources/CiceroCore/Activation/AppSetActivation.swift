import CoreText
import Foundation

extension ActivationEngine {
    /// Brings application sets' fonts in line with `wanted`: each file's path → the bundle IDs of the
    /// open apps whose sets have it. Files that are off get registered for the session; files already on
    /// for application sets keep going with the apps that still want them, and the ones no open app wants
    /// are unregistered. Files that are on for any other reason are left alone, so an application set
    /// never turns off a font the user turned on.
    /// `faces` has each wanted file's face, for its current state. Like temporary activation, a file
    /// counts as on only once macOS reports it active.
    @concurrent
    public func syncAppSets(_ wanted: [String: Set<String>], faces: [String: LibraryFace], records: ActivationRecords) async -> ActivationResult {
        var records = records
        var release: [String] = []
        for (path, record) in records.temporary where record.scope == .whileAppsRun {
            if let apps = wanted[path], !apps.isEmpty {
                records.temporary[path]?.apps = apps.sorted()
            } else {
                release.append(path)
            }
        }
        let register = wanted.keys.filter { path in
            guard !(wanted[path] ?? []).isEmpty, records.temporary[path] == nil, let face = faces[path] else { return false }
            return !face.state.isActive
        }.sorted()

        if !release.isEmpty {
            // One that won't unregister keeps its record, so the next sync tries again.
            let stuck = await registrar.unregister(release.map { URL(fileURLWithPath: $0) }, scope: .session)
            for path in release where !stuck.contains(path) { records.temporary[path] = nil }
        }
        var failed: [String] = []
        var succeeded = 0
        if !register.isEmpty {
            let session = Self.currentSession()
            let stuck = await registerAndConfirm(register, scope: .session)
            for path in register {
                if stuck.contains(path) {
                    failed.append(path)
                } else {
                    records.temporary[path] = TemporaryRecord(scope: .whileAppsRun, session: session, apps: wanted[path]?.sorted())
                    succeeded += 1
                }
            }
        }
        let message = failed.isEmpty
            ? (succeeded == 1 ? "Activated 1 file" : "Activated \(succeeded) files")
            : "Couldn’t activate \(failed.count) of \(failed.count + succeeded) files"
        return ActivationResult(records: records, succeeded: succeeded, failed: failed, message: message)
    }
}
