import PointCore
import SwiftUI

struct FoldersSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    /// The folder being marked as loaded by an app Point doesn't know.
    @State private var namingFolder: WatchedFolder?
    @State private var appName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fonts in these folders are in your library without being installed. For a folder an app loads by itself, its fonts count as active in that app.")
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
            .alternatingRowBackgrounds()
            HStack(spacing: 6) {
                Button("Add Folder", systemImage: "plus") { model.presentAddFolderPanel() }
                    .help("Add a folder of fonts")
                Button("Remove Folder", systemImage: "minus") {
                    if let selection { model.removeFolder(selection) }
                    selection = nil
                }
                .disabled(selection == nil)
                .help("Remove the folder from the library; its files stay where they are")
            }
            .labelStyle(.iconOnly)
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
            Text("Point lists the fonts in “\(folder.displayName)” as active in that app, which loads them by itself.")
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
            Image(systemName: folder.appName == nil ? "folder" : "folder.badge.gearshape")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Picker("Fonts in This Folder", selection: Binding(
                get: { folder.appName ?? "" },
                set: { $0 == Self.otherApp ? nameApp() : model.setAppName($0, forFolder: folder.id) }
            )) {
                Text("Not activated until you activate them").tag("")
                ForEach(apps, id: \.self) { Text("Active in \(FaceState.appDescription($0))").tag($0) }
                Divider()
                Text("Active in another app…").tag(Self.otherApp)
            }
            .labelsHidden()
            .fixedSize()
        }
        .tag(folder.id)
    }

    private var apps: [String] {
        var apps = ["Adobe", "InDesign"]
        if let custom = folder.appName, !apps.contains(custom) { apps.append(custom) }
        return apps
    }
}
