import AppKit
import CiceroCore

struct ToastAction {
    let title: String
    let run: @MainActor (AppModel) -> Void
}

struct VaultAddPrompt: Identifiable {
    let id = UUID()
    var draft: VaultDraft
    var owner = ""
}

struct LicenseMatch {
    var style: VaultLicense.Style
    var family: Family?
    var face: LibraryFace?
}

extension AppModel {
    var vault: Vault { Vault(locations: locations) }

    var vaultOwners: [String] {
        var seen = Set<String>()
        return vaultLicenses.map(\.owner).filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func reloadVault() {
        let vault = vault
        let generation = vaultGeneration
        Task {
            let licenses = await Task.detached(priority: .userInitiated) { vault.licenses() }.value
            guard generation == vaultGeneration else { return }
            vaultRevision &+= 1
            if licenses != vaultLicenses { vaultLicenses = licenses }
            if let id = openLicenseID, !licenses.contains(where: { $0.id == id }) { openLicenseID = nil }
            keepVaultSelection()
        }
    }

    func vaultOwnerItem(_ owner: String) -> SidebarItem? {
        vaultOwners.first { $0.lowercased() == owner.lowercased() }.map { .vaultOwner($0) }
    }

    private func keepVaultSelection() {
        guard selectedItems.contains(where: { $0.vaultOwner != nil }) else { return }
        let kept = Set(selectedItems.compactMap { item in item.vaultOwner.map(vaultOwnerItem) ?? item })
        guard kept != selectedItems else { return }
        let open = openLicenseID
        if kept.isEmpty {
            selection = .vault
        } else if kept.count == 1 {
            selection = kept.first
        } else {
            selectSidebarItems(kept)
        }
        openLicenseID = open
    }

    func showVaultFolders(of items: [SidebarItem]) {
        let root = vault.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = items.compactMap { item -> URL? in
            guard let owner = item.vaultOwner else { return item == .vault ? root : nil }
            return vaultLicenses.first { $0.owner.lowercased() == owner.lowercased() }?.folder.deletingLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting(folders)
    }

    func cleanUpVault() {
        let vault = vault
        let start = Date()
        Task {
            await Task.detached(priority: .userInitiated) { vault.removeLeftoverStaging(olderThan: start) }.value
            reloadVault()
        }
    }

    private func vaultChanged() {
        vaultGeneration &+= 1
        vaultRevision &+= 1
    }

    func presentAddToVaultPanel(owner: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose licenses, receipts, fonts, web fonts or a ZIP file. Cicero copies them into the Vault. The originals stay where they are."
        guard panel.runModal() == .OK else { return }
        addToVault(panel.urls, owner: owner)
    }

    func addToVault(_ urls: [URL], owner: String? = nil) {
        let vault = vault
        let items = urls.filter(\.isFileURL).map(\.standardizedFileURL).filter { !vault.holdsOrIsIn($0.path) }
        guard !items.isEmpty else { return showToast(urls.count == 1 ? "That’s the Vault or a file in it" : "Those are the Vault or files in it") }
        guard !isAddingToVault else { return }
        isAddingToVault = true
        Task {
            defer { isAddingToVault = false }
            do {
                let draft = try await Task.detached(priority: .userInitiated) { try vault.stage(items) }.value
                ask { $0.vaultAdd = VaultAddPrompt(draft: draft, owner: owner ?? "") }
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func cancelAdding(_ prompt: VaultAddPrompt) {
        vaultAdd = nil
        let vault = vault
        Task.detached(priority: .utility) { vault.discard(prompt.draft) }
    }

    func finishAdding(_ prompt: VaultAddPrompt, as license: VaultLicense) {
        vaultAdd = nil
        let vault = vault
        Task {
            do {
                let added = try await Task.detached(priority: .userInitiated) { try vault.add(prompt.draft, as: license) }.value
                vaultChanged()
                vaultLicenses.append(added)
                vaultLicenses = vault.sorted(vaultLicenses)
                selection = selection?.vaultOwner == nil ? .vault : vaultOwnerItem(added.owner)
                openLicenseID = added.id
                showToast("“\(added.name)” is in the Vault")
            } catch {
                Task.detached(priority: .utility) { vault.discard(prompt.draft) }
                showToast("Couldn’t add the files to the Vault: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func saveLicense(_ license: VaultLicense) -> VaultLicense? {
        guard let index = vaultLicenses.firstIndex(where: { $0.id == license.id }) else { return nil }
        guard vaultLicenses[index] != license else { return license }
        do {
            let before = vaultLicenses[index].folder.deletingLastPathComponent()
            let saved = try vault.save(license)
            vaultChanged()
            let ownerBefore = vaultLicenses[index].owner
            vaultLicenses[index] = saved
            vaultLicenses = vault.sorted(vaultLicenses)
            let oldOwner = ownerBefore.lowercased()
            if saved.owner.lowercased() != oldOwner, selectedItems.contains(where: { $0.vaultOwner?.lowercased() == oldOwner }),
               let item = vaultOwnerItem(saved.owner) {
                let items = Set(selectedItems.map { $0.vaultOwner?.lowercased() == oldOwner ? item : $0 })
                let open = openLicenseID
                if items.count == 1 { selection = item } else { selectSidebarItems(items) }
                openLicenseID = open
            }
            keepVaultSelection()
            if saved.folder.deletingLastPathComponent().lastPathComponent != before.lastPathComponent { reloadVault() }
            return saved
        } catch {
            showToast("Couldn’t save “\(license.name)”: \(error.localizedDescription)")
            reloadVault()
            return nil
        }
    }

    func addFiles(_ urls: [URL], to license: VaultLicense) {
        let vault = vault
        let items = urls.filter(\.isFileURL).map(\.standardizedFileURL).filter { !vault.holdsOrIsIn($0.path) }
        guard !items.isEmpty else { return showToast(urls.count == 1 ? "That’s the Vault or a file in it" : "Those are the Vault or files in it") }
        Task {
            do {
                let changed = try await Task.detached(priority: .userInitiated) { try vault.addFiles(items, to: license) }.value
                vaultChanged()
                if let index = vaultLicenses.firstIndex(where: { $0.id == license.id }) { vaultLicenses[index] = changed }
                showToast(items.count == 1 ? "Added “\(items[0].lastPathComponent)”" : "Added \(items.count.plain) items")
            } catch {
                showToast("Couldn’t add the files: \(error.localizedDescription)")
            }
        }
    }

    func trash(_ license: VaultLicense) {
        trashingLicense = nil
        do {
            _ = try vault.trash(license)
            vaultChanged()
            vaultLicenses.removeAll { $0.id == license.id }
            if openLicenseID == license.id { openLicenseID = nil }
            keepVaultSelection()
            showToast("Moved “\(license.name)” to the Trash")
        } catch {
            showToast("Couldn’t move “\(license.name)” to the Trash: \(error.localizedDescription)")
        }
    }

    func showInFinder(_ license: VaultLicense, file: VaultFile? = nil) {
        let url = file.map { license.folder.appendingPathComponent($0.path) } ?? license.folder
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func licenses(of family: Family) -> [VaultLicense] {
        vaultLicenses.filter { !coveredFaces(of: family, by: $0).isEmpty }
    }

    func coveredFaces(of family: Family, by license: VaultLicense) -> [LibraryFace] {
        let styles = license.styles
        return family.faces.filter { face in
            styles.contains { style in
                style.postScriptName.lowercased() == face.face.postScriptName.lowercased()
                    || (!Self.vaultFamilyKey(style.family).isEmpty && Self.vaultFamilyKey(style.family) == Self.vaultFamilyKey(face.face.familyName)
                        && Self.vaultStyleKey(style.style) == Self.vaultStyleKey(face.face.styleName))
            }
        }
    }

    func matches(for license: VaultLicense) -> [LicenseMatch] {
        let matcher = FontMatcher(library)
        return license.styles.map { style in
            var found = matcher.faces(ImportedFont(postScriptName: style.postScriptName, family: style.family, style: style.style)).first
            if found == nil, Self.vaultFamilyKey(style.family) != style.family.lowercased() {
                found = matcher.faces(ImportedFont(family: Self.withoutWeb(style.family), style: style.style)).first
            }
            return LicenseMatch(style: style, family: found?.family, face: found?.face)
        }
    }

    static func vaultFamilyKey(_ name: String) -> String {
        withoutWeb(name).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func vaultStyleKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Web fonts are often named like their desktop family with "Web" after it, as in "Söhne Web".
    static func withoutWeb(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: #/(.+\S)\s+[Ww][Ee][Bb]/#) else { return trimmed }
        return String(match.1)
    }

    static func versionNumber(_ version: String?) -> String? {
        guard let version else { return nil }
        let match = version.firstMatch(of: #/\d+(\.\d+)+/#)
        return match.map { String($0.output.0) } ?? version
    }
}

extension SidebarItem {
    var isVault: Bool { self == .vault || vaultOwner != nil }

    var vaultOwner: String? {
        if case .vaultOwner(let owner) = self { owner } else { nil }
    }
}

extension Vault {
    func sorted(_ licenses: [VaultLicense]) -> [VaultLicense] {
        licenses.sorted {
            let owner = $0.owner.localizedStandardCompare($1.owner)
            return owner == .orderedSame ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : owner == .orderedAscending
        }
    }
}
