import AppKit
import CiceroCore
import UniformTypeIdentifiers

extension AppModel {
    /// Asks for a name, makes the set and shows its apps, so the next step is picking one.
    func newApplicationSet(with families: [Family] = []) {
        prompt("New App Folder", confirm: "Create") { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let set = FontSet(name: trimmed, families: families.map(\.id))
            self.data.sets.append(set)
            self.data.sidebar.hidden.remove(SidebarSection.sets.key)
            self.selection = .set(set.id)
            self.editingAppsForSet = set.id
        }
    }

    /// Picks apps for a set from /Applications.
    func presentAppPicker(for setID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        panel.message = "Choose the apps that need this folder’s fonts."
        guard panel.runModal() == .OK else { return }
        addApps(panel.urls, to: setID)
    }

    func addApps(_ urls: [URL], to setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        var apps = data.sets[index].apps
        for url in urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !apps.contains(where: { $0.bundleID == bundleID }) else { continue }
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            apps.append(LinkedApp(bundleID: bundleID, name: name, path: url.path))
        }
        data.sets[index].apps = apps
    }

    func removeApp(_ bundleID: String, from setID: UUID) {
        guard let index = data.sets.firstIndex(where: { $0.id == setID }) else { return }
        data.sets[index].apps.removeAll { $0.bundleID == bundleID }
    }
}
