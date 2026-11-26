import CoreText
import Foundation

extension ActivationEngine {
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
            let stuck = await endSessionRegistrations(release)
            for path in release where !stuck.contains(path) { records.temporary[path] = nil }
        }
        var failed: [String] = []
        var succeeded = 0
        if !register.isEmpty {
            Self.stopKeepingOff(register)
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
