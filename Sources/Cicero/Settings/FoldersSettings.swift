import CiceroCore
import SwiftUI

struct FoldersSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    /// The folder being marked as loaded by an app Cicero doesn't know.
    @State private var namingFolder: WatchedFolder?
    @State private var appName = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("Fonts in these folders are in your library without being installed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(model.data.folders) { folder in
                    FolderRow(folder: folder, model: model) {
                        appName = ""
                        namingFolder = folder
                    }
                }
            }
            .listStyle(.bordered)
            // No stripes behind the empty-state note.
            .alternatingRowBackgrounds(model.data.folders.isEmpty ? .disabled : .enabled)
            .overlay {
                if model.data.folders.isEmpty {
                    Text("Add a folder of fonts to browse them without installing them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            HStack(spacing: 2) {
                ListEditButton("Add Folder", systemImage: "plus") { model.presentAddFolderPanel() }
                    .help("Add a folder of fonts")
                ListEditButton("Remove Folder", systemImage: "minus") {
                    if let selection { model.removeFolder(selection) }
                    selection = nil
                }
                .disabled(selection == nil)
                .help("Remove the folder from the library; its files stay where they are")
            }
            Divider()
                .padding(.vertical, 6)
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show fonts installed for Adobe apps")
                    Text("Listed under Adobe Apps in the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Show fonts installed for Adobe apps", isOn: $model.data.showAdobeFonts)
                    .toggleStyle(.switch)
                    // The size grouped forms give switches, as in the other tabs: outside one it's the regular size.
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
        .padding(20)
        .alert(
            "Active in Another App",
            isPresented: Binding(get: { namingFolder != nil }, set: { if !$0 { namingFolder = nil } }),
            presenting: namingFolder
        ) { folder in
            TextField("App name", text: $appName, prompt: Text("App name"))
            Button("OK") { model.setAppName(appName, forFolder: folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Cicero lists the fonts in “\(folder.displayName)” as active in that app, which loads them by itself.")
        }
    }
}

private struct FolderRow: View {
    let folder: WatchedFolder
    let model: AppModel
    let nameApp: () -> Void

    /// Picking this asks for an app name instead of storing a value.
    private static let otherApp = "\u{0}other"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.availability(ofFolder: folder.id) != nil ? "questionmark.folder"
                  : folder.appName == nil ? "folder" : "folder.badge.gearshape")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
            }
            Spacer()
            Picker("Fonts in This Folder", selection: Binding(
                get: { folder.appName ?? "" },
                set: { $0 == Self.otherApp ? nameApp() : model.setAppName($0, forFolder: folder.id) }
            )) {
                Text("Not activated until you activate them").tag("")
                ForEach(apps, id: \.self) { Text("Active in \(FaceState.appDescription($0))").tag($0) }
                Divider()
                Text("Active in another app").tag(Self.otherApp)
            }
            .labelsHidden()
            .fixedSize()
        }
        .tag(folder.id)
    }

    /// What's out of reach in the folder, if anything.
    @ViewBuilder
    private var status: some View {
        let onlineOnly = model.onlineOnlyCount(inFolder: folder.id)
        switch model.availability(ofFolder: folder.id) {
        case .notFound:
            let volume = Reachability.disconnectedVolume(of: folder.path)
            warning(volume.map { "“\($0)” isn’t connected" } ?? "Can’t be found")
        case .noAccess:
            HStack(spacing: 6) {
                warning("Cicero isn’t allowed to read it")
                Button("Allow") { model.openFilesAndFoldersSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Open Privacy & Security in System Settings, where Files and Folders lets Cicero in")
            }
        case nil where model.downloads[folder.id] != nil:
            let progress = model.downloads[folder.id]!
            Text("Downloading \(progress.done.formatted()) of \(progress.total.formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
        case nil where onlineOnly > 0:
            HStack(spacing: 6) {
                Label(onlineOnly == 1 ? "1 font file is online only" : "\(onlineOnly.formatted()) font files are online only", systemImage: "icloud.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download") { model.downloadOnlineOnlyFonts(inFolder: folder.id) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Download them from the cloud service so they’re listed")
            }
        case nil:
            EmptyView()
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var apps: [String] {
        var apps = ["Adobe", "InDesign"]
        if let custom = folder.appName, !apps.contains(custom) { apps.append(custom) }
        return apps
    }
}
