import Foundation
import SwiftUI

/// Fonts to move to the Trash, worked out before asking for confirmation.
struct TrashRequest: Identifiable {
    let id = UUID()
    var title: String
    /// Every file to trash: active copies and the copies in other folders.
    var paths: [String]
    /// Families that keep some styles in those files without being part of the request (collections).
    var otherFamilies: [String]
    /// Families with files Point won't touch, like fonts that come with macOS.
    var protectedCount: Int
    var familyNames: [String]
}

/// Removing fonts from the Mac. Files always go to the Trash, so they can be put back.
extension LibraryStore {
    func requestTrash(_ families: [FontFamily]) {
        requestTrash(faces: families.flatMap(\.faces), title: families.count == 1 ? "“\(families[0].name)”" : "\(families.count) families",
                     familyNames: families.map(\.name))
    }

    func requestTrash(faces: [LibraryFace], title: String, familyNames: [String] = []) {
        var paths: [String] = []
        var seen = Set<String>()
        var protected = 0
        for face in faces {
            for path in [face.face.path] + face.otherPaths where seen.insert(path).inserted {
                if Self.mayTrash(path) { paths.append(path) } else { protected += 1 }
            }
        }
        guard !paths.isEmpty else {
            showToast("Fonts that come with macOS or an app can’t be moved to the Trash.")
            return
        }
        let requested = Set(familyNames)
        let pathSet = Set(paths)
        let others = families.filter { family in
            !requested.contains(family.name) && family.faces.contains { pathSet.contains($0.face.path) }
        }
        pendingTrash = TrashRequest(title: title, paths: paths, otherFamilies: others.map(\.name),
                                    protectedCount: protected, familyNames: familyNames)
    }

    func trash(_ request: TrashRequest) async {
        let fm = FileManager.default
        await endTemporaryActivation(of: request.paths)
        let registered = request.paths.filter(data.registeredPaths.contains)
        if !registered.isEmpty {
            let urls = registered.map { URL(fileURLWithPath: $0) }
            _ = await CoreTextRegistration.unregister(urls, scope: .persistent)
            _ = await CoreTextRegistration.unregister(urls, scope: .session)
        }
        var failures = 0
        for path in request.paths {
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                data.registeredPaths.remove(path)
                data.installedCopies.removeValue(forKey: path)
            } catch {
                NSLog("Point: moving \(path) to the Trash failed: \(error)")
                failures += 1
            }
        }
        if failures == 0 {
            for name in request.familyNames { forget(familyNamed: name) }
            showToast(request.paths.count == 1 ? "Moved to the Trash." : "Moved \(request.paths.count) files to the Trash.")
        } else {
            showToast("Couldn’t move \(failures) of \(request.paths.count) files to the Trash.")
        }
        save()
        scheduleRescan(after: 0.8)
    }

    /// Drops a removed family from sets, tags and foundry overrides.
    private func forget(familyNamed name: String) {
        for index in data.sets.indices { data.sets[index].familyNames.removeAll { $0 == name } }
        data.familyTags.removeValue(forKey: name)
        data.foundryOverrides.removeValue(forKey: name)
        selectedFamilyIDs.remove(name)
        if detailFamilyID == name { detailFamilyID = nil }
    }

    /// Fonts that come with macOS, apps or Adobe's cloud fonts are managed by them, not by people.
    static func mayTrash(_ path: String) -> Bool {
        let protectedPrefixes = ["/System/", "/Library/Application Support/Apple/", "/usr/", "/private/"]
        if protectedPrefixes.contains(where: path.hasPrefix) { return false }
        if path.contains(".app/") || path.contains("/Adobe/CoreSync/") { return false }
        return true
    }
}

/// The confirmation for moving fonts to the Trash, attachable to any window.
struct FontTrashAlert: ViewModifier {
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content.alert(
            library.pendingTrash.map { "Move \($0.title) to the Trash?" } ?? "",
            isPresented: Binding(get: { library.pendingTrash != nil }, set: { if !$0 { library.pendingTrash = nil } }),
            presenting: library.pendingTrash
        ) { request in
            Button("Move to Trash", role: .destructive) { Task { await library.trash(request) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(message(for: request))
        }
    }

    private func message(for request: TrashRequest) -> String {
        var parts = [request.paths.count == 1
            ? "1 font file will be removed from your Mac and turned off in every app."
            : "\(request.paths.count) font files, including copies in other folders, will be removed from your Mac and turned off in every app."]
        if !request.otherFamilies.isEmpty {
            let names = ListFormatter.localizedString(byJoining: Array(request.otherFamilies.prefix(3)))
            parts.append("Some files also contain \(names)\(request.otherFamilies.count > 3 ? " and others" : ""), which will be removed too.")
        }
        if request.protectedCount > 0 {
            parts.append("Files that come with macOS or an app stay where they are.")
        }
        parts.append(request.paths.count == 1 ? "You can put it back from the Trash." : "You can put them back from the Trash.")
        return parts.joined(separator: " ")
    }
}
