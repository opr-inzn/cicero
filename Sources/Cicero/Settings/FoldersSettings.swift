import CiceroCore
import SwiftUI

struct FoldersSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<UUID> = []
    /// The folder being marked as loaded by an app Cicero doesn't know.
    @State private var namingFolder: WatchedFolder?
    @State private var appName = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(model.data.folders.enumerated()), id: \.element.id) { index, folder in
                FolderRow(folder: folder, model: model) {
                    appName = ""
                    namingFolder = folder
                }
                .cardRow(index)
            }
        }
        .overlay {
            if model.data.folders.isEmpty {
                Text("Add a folder of fonts to browse them without activating them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .inCard(
            add: CardListButton(title: "Add Location", help: "Add a folder of fonts") { model.presentAddFolderPanel() },
            remove: CardListButton(title: "Remove Locations", help: "Remove the selected locations from the library; their files stay where they are") {
                model.removeFolders(selection)
                selection = []
            },
            canRemove: !selection.isEmpty
        )
        .padding(20)
        .alert(
            "Active in Specific App",
            isPresented: Binding(get: { namingFolder != nil }, set: { if !$0 { namingFolder = nil } }),
            presenting: namingFolder
        ) { folder in
            TextField("App name", text: $appName, prompt: Text("App name"))
            Button("OK") { model.setActivation(ofFolder: folder.id, active: false, app: appName) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Cicero lists the fonts in “\(model.data.named(folder).displayName)” as active in that app, which loads them by itself.")
        }
    }
}

private struct FolderRow: View {
    let folder: WatchedFolder
    let model: AppModel
    let nameApp: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.availability(ofFolder: folder.id) != nil ? "questionmark.folder" : "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.data.named(folder).displayName)
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
            }
            Spacer()
            FolderActivationPicker(folder: folder, askForApp: nameApp)
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
            warning("Can’t be found")
        case .disconnected(let volume):
            warning("“\(volume)” isn’t connected")
        case .noAccess:
            HStack(spacing: 6) {
                warning("Cicero isn’t allowed to read it")
                Button("Allow") { model.openFilesAndFoldersSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Open Privacy & Security in System Settings, where Files and Folders lets Cicero in")
            }
        case nil:
            if let progress = model.downloads[folder.id] {
                Text("Downloading \(progress.done.formatted()) of \(progress.total.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if onlineOnly > 0 {
                HStack(spacing: 6) {
                    Label(onlineOnly == 1 ? "1 font file is online only" : "\(onlineOnly.formatted()) font files are online only", systemImage: "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Download") { model.downloadOnlineOnlyFonts(inFolder: folder.id) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Download them from the cloud service so they’re listed")
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
