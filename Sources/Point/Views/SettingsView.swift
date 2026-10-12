import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Folders", systemImage: "folder") { FoldersSettings() }
            Tab("Activation", systemImage: "power") { ActivationSettings() }
            Tab("Sidebar", systemImage: "sidebar.left") { SidebarSettings() }
            Tab("Character Sets", systemImage: "character.textbox") { CharacterSetSettings() }
        }
        .frame(width: 560, height: 580)
    }
}

// MARK: - Folders

private struct FoldersSettings: View {
    @Environment(LibraryStore.self) private var library
    @State private var selection: UUID?
    @State private var customAppFolder: UUID?
    @State private var customAppName = ""

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders").font(.headline)
            Text("Fonts in these folders show up in your library but stay off until you activate them. If an app loads a folder by itself, like Adobe’s Fonts folder, mark it so its fonts count as on in that app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(library.data.watchedFolders) { folder in
                    folderRow(folder).tag(folder.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(minHeight: 280)

            HStack(spacing: 0) {
                Button { library.presentAddFolderPanel() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                Divider().frame(height: 16)
                Button {
                    if let selection { library.removeFolder(selection) }
                    selection = nil
                } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                .disabled(selection == nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .alert("Which app loads these fonts?", isPresented: Binding(get: { customAppFolder != nil }, set: { if !$0 { customAppFolder = nil } })) {
            TextField("App name", text: $customAppName)
            Button("Save") {
                if let id = customAppFolder { library.setAppOnlyName(customAppName, forFolder: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fonts in this folder will show as active in that app instead of inactive.")
        }
    }

    private func folderRow(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: folder.appOnlyName == nil ? "folder" : "folder.badge.gearshape")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.displayName)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                Button { library.setAppOnlyName(nil, forFolder: folder.id) } label: {
                    selectable("Inactive until activated", folder.appOnlyName == nil)
                }
                Button { library.setAppOnlyName("Adobe", forFolder: folder.id) } label: {
                    selectable("Active in Adobe apps", folder.appOnlyName == "Adobe")
                }
                if let custom = folder.appOnlyName, custom != "Adobe" {
                    Button {} label: { selectable("Active in \(custom) apps", true) }
                }
                Divider()
                Button("Active in Another App…") {
                    customAppName = ""
                    customAppFolder = folder.id
                }
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
            } label: {
                Text(folder.appOnlyName.map { "\($0) only" } ?? "Inactive")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func selectable(_ title: String, _ selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

// MARK: - Sidebar

/// Finder-style list of every sidebar item with a checkbox. Shares state with the sidebar's Edit mode.
private struct SidebarSettings: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show these items in the sidebar:")
            List {
                Section("Library") {
                    ForEach(library.libraryRows) { checkbox($0.key, $0.title, $0.icon) }
                }
                Section("Groups") {
                    ForEach(SidebarSection.allCases) { section in
                        checkbox(section.key, section.title, section.icon)
                    }
                }
                ForEach(SidebarSection.allCases) { section in
                    let rows = library.rows(for: section)
                    if !rows.isEmpty {
                        Section(section.title) {
                            ForEach(rows) { checkbox($0.key, $0.title, $0.icon) }
                        }
                        .disabled(!library.isVisible(section.key))
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            HStack {
                Text("You can also click Edit next to Library in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All") { library.showAllSidebarItems() }
                    .disabled(library.data.hiddenSidebarItems.isEmpty)
            }
        }
        .padding(20)
    }

    private func checkbox(_ key: String, _ title: String, _ icon: String) -> some View {
        Toggle(isOn: library.visibilityBinding(for: key)) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
            }
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(LibraryStore.self) private var library
    @State private var isConfirmingCacheClear = false
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { appearance.apply() }
            }
            Section {
                Toggle("Show system fonts in other lists", isOn: $library.data.showSystemFonts)
                    .onChange(of: library.data.showSystemFonts) { library.save() }
                Text("Fonts that ship with macOS (in /System/Library/Fonts) can’t be turned off. Turn this off to list them only under System Fonts in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Font Caches") {
                LabeledContent("Point’s font list") {
                    Button("Rebuild") { library.rebuildFontList() }
                        .disabled(library.isScanning)
                }
                LabeledContent("macOS, Adobe and Office caches") {
                    Button("Clear…") { isConfirmingCacheClear = true }
                }
                Text("If fonts look wrong, show an old version, or won’t turn on or off, clearing the caches usually fixes it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .modifier(FontCacheDialogs(isConfirming: $isConfirmingCacheClear))
    }
}

// MARK: - Activation

private struct ActivationSettings: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Activate by", selection: $library.data.installMethod) {
                    ForEach(InstallMethod.allCases, id: \.self) { Text($0.settingsLabel).tag($0) }
                }
                .onChange(of: library.data.installMethod) { library.save() }
                Text("A copy in ~/Library/Fonts keeps working if the original files move or their drive is unplugged. Using the files where they are saves space, but the fonts turn off when those files go away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
