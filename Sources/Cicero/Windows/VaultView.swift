import AppKit
import CiceroCore
import QuickLook
import SwiftUI

struct VaultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let license = model.openLicenseID.flatMap({ id in model.vaultLicenses.first { $0.id == id } }) {
                LicensePage(original: license).id(license.id)
            } else {
                VaultList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .task { model.reloadVault() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reloadVault() }
        .alert(
            model.trashingLicense.map { "Move “\($0.name)” for \($0.owner) to the Trash?" } ?? "",
            isPresented: Binding(get: { model.trashingLicense != nil }, set: { if !$0 { model.trashingLicense = nil } }),
            presenting: model.trashingLicense
        ) { license in
            Button("Move to Trash", role: .destructive) { model.trash(license) }
            Button("Cancel", role: .cancel) {}
        } message: { license in
            let count = Vault.files(in: license.folder).count
            Text("\(count == 1 ? "Its file goes" : "Its \(count.plain) files go") to the Trash with it. You can put \(count == 1 ? "it" : "them") back from the Trash. The fonts in your library stay where they are.")
        }
    }
}

extension VaultLicense.Kind {
    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .web: "Web"
        case .app: "App"
        case .trial: "Trial"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .desktop: .green
        case .web: .blue
        case .app: .purple
        case .trial: .orange
        case .other: .gray
        }
    }
}

struct KindChips: View {
    let kinds: [VaultLicense.Kind]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(kinds, id: \.self) { kind in
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(kind.color)
                    .background(kind.color.opacity(0.14), in: .rect(cornerRadius: 5))
            }
        }
    }
}

struct EndsLabel: View {
    let ends: Date?

    var body: some View {
        if let ends {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: ends)).day ?? 0
            VStack(alignment: .leading, spacing: 1) {
                Text(ends, format: .dateTime.day().month(.abbreviated).year())
                if days < 0 {
                    Text("Ended").font(.caption)
                } else if days <= 14 {
                    Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days.plain) days").font(.caption)
                }
            }
            .foregroundStyle(days <= 14 ? Color.orange : Color.primary)
        } else {
            Text("No end").foregroundStyle(.secondary)
        }
    }
}

// MARK: - List

private struct VaultList: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<UUID>()

    private struct OwnerGroup: Identifiable {
        let owner: String
        let licenses: [VaultLicense]
        var id: String { owner }
    }

    var body: some View {
        let shown = shownLicenses
        let groups = grouped(shown)
        Group {
            if model.vaultLicenses.isEmpty {
                EmptyState("No Licenses", systemImage: "archivebox",
                           description: Text("Drop licenses, receipts, web fonts or a foundry’s ZIP file here.\nCicero copies them into the Vault, and the originals stay where they are.")) {
                    Button("Add Files…") { model.presentAddToVaultPanel() }
                }
            } else if shown.isEmpty {
                EmptyState.search(text: model.searchText)
            } else {
                Table(of: VaultLicense.self, selection: $selection) {
                    TableColumn("License") { license in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(license.name)
                            if !license.families.isEmpty {
                                Text(license.families.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 160, ideal: 220)
                    TableColumn("Styles") { license in
                        Text(license.styles.isEmpty ? "None" : license.styles.count == 1 ? "1 style" : "\(license.styles.count.plain) styles")
                            .foregroundStyle(license.styles.isEmpty ? .secondary : .primary)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Kind") { KindChips(kinds: $0.kinds) }
                        .width(min: 80, ideal: 120)
                    TableColumn("Project or Domain") { license in
                        Text(license.project.isEmpty ? "None" : license.project)
                            .foregroundStyle(license.project.isEmpty ? .secondary : .primary)
                    }
                    .width(min: 100, ideal: 160)
                    TableColumn("Added") { Text($0.added, format: .dateTime.day().month(.abbreviated).year()) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Ends") { EndsLabel(ends: $0.ends) }
                        .width(min: 80, ideal: 100)
                } rows: {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.licenses) { TableRow($0) }
                        } header: {
                            Text(group.owner).bold() + Text("  \(group.licenses.count == 1 ? "1 license" : "\(group.licenses.count.plain) licenses")").foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    let chosen = model.vaultLicenses.filter { ids.contains($0.id) }
                    if chosen.count == 1 {
                        Button("Open") { model.openLicenseID = chosen[0].id }
                        Button("Show in Finder") { model.showInFinder(chosen[0]) }
                        Divider()
                        Button("Move to Trash…") { model.trashingLicense = chosen[0] }
                    } else if chosen.count > 1 {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(chosen.map(\.folder)) }
                    }
                } primaryAction: { ids in
                    if ids.count == 1 { model.openLicenseID = ids.first }
                }
            }
        }
        .topBar {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox").foregroundStyle(.secondary)
                    Text("Licenses and the files that come with them. Fonts in the Vault stay out of your library.")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Files…") { model.presentAddToVaultPanel() }
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }
            .topBarTint()
        }
        .navigationTitle("Vault")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let licenses = model.vaultLicenses.count
        guard licenses > 0 else { return "" }
        let owners = model.vaultOwners.count
        return "\(licenses == 1 ? "1 License" : "\(licenses.plain) Licenses") · \(owners == 1 ? "1 Owner" : "\(owners.plain) Owners")"
    }

    private var shownLicenses: [VaultLicense] {
        let words = model.searchText.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return model.vaultLicenses }
        return model.vaultLicenses.filter { license in
            let text = ([license.owner, license.name, license.project, license.note] + license.families + license.kinds.map(\.title)).joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    private func grouped(_ licenses: [VaultLicense]) -> [OwnerGroup] {
        var order: [String] = []
        var byOwner: [String: [VaultLicense]] = [:]
        for license in licenses {
            let key = license.owner.lowercased()
            if byOwner[key] == nil { order.append(key) }
            byOwner[key, default: []].append(license)
        }
        return order.map { OwnerGroup(owner: byOwner[$0]![0].owner, licenses: byOwner[$0]!) }
    }
}

// MARK: - License page

private struct LicensePage: View {
    @Environment(AppModel.self) private var model
    @State private var license: VaultLicense
    @State private var files: [VaultFile] = []
    @State private var matches: [LicenseMatch] = []
    @State private var endsOn: Bool
    @State private var hasDate: Bool
    @State private var previewed: URL?

    init(original: VaultLicense) {
        _license = State(initialValue: original)
        _endsOn = State(initialValue: original.ends != nil)
        _hasDate = State(initialValue: original.date != nil)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                details.frame(width: 400)
                VStack(alignment: .leading, spacing: 24) {
                    stylesSection
                    filesSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .topBar {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        save()
                        model.openLicenseID = nil
                    } label: {
                        Label("Vault", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Spacer()
                    Button("Show in Finder") { model.showInFinder(license) }
                    Button("Move to Trash…") {
                        save()
                        model.trashingLicense = license
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }
            .topBarTint()
        }
        .navigationTitle(license.name)
        .navigationSubtitle(license.owner)
        .quickLookPreview($previewed)
        .task(id: StoredKey(license: model.vaultLicenses.first { $0.id == license.id }, revision: model.vaultRevision)) { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in save() }
        .task(id: license) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
        .onDisappear { save() }
    }

    private func refresh() {
        if let stored = model.vaultLicenses.first(where: { $0.id == license.id }) {
            license.styles = stored.styles
            license.folder = stored.folder
        }
        files = Vault.files(in: license.folder)
        matches = model.matches(for: license)
    }

    private func save() {
        var edited = license
        edited.owner = edited.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.owner.isEmpty, !edited.name.isEmpty else { return }
        guard let saved = model.saveLicense(edited) else { return }
        if saved.folder != license.folder { license.folder = saved.folder }
        if saved.name != edited.name { license.name = saved.name }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").font(.headline)
            Form {
                OwnerField(owner: $license.owner, owners: model.vaultOwners)
                TextField("Name", text: $license.name)
                LabeledContent("Kind") { KindToggles(kinds: $license.kinds) }
                TextField("Project or domain", text: $license.project, prompt: Text("Optional"))
                LabeledContent("Date") {
                    HStack {
                        Toggle("Date", isOn: $hasDate).labelsHidden()
                        DatePicker("Date", selection: Binding(get: { license.date ?? .now }, set: { license.date = $0 }), displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!hasDate)
                    }
                }
                .onChange(of: hasDate) { license.date = $1 ? (license.date ?? .now) : nil }
                LabeledContent("Ends") {
                    HStack {
                        Toggle("Ends", isOn: $endsOn).labelsHidden()
                        DatePicker("Ends", selection: Binding(get: { license.ends ?? .now }, set: { license.ends = $0 }), displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!endsOn)
                    }
                }
                .onChange(of: endsOn) { license.ends = $1 ? (license.ends ?? .now) : nil }
                TextField("Note", text: $license.note, prompt: Text("Seats, order number, whom to ask"), axis: .vertical)
                    .lineLimit(3...8)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
            Text("Kept in \(Self.shortPath(license.folder))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Styles").font(.headline)
                Text(stylesSummary).foregroundStyle(.secondary)
                Spacer()
            }
            if matches.isEmpty {
                Text("No font files in this license. Add them, and Cicero links their styles to your library.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Style")
                        Text("Version Here")
                        Text("Your Library")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(matches, id: \.style.postScriptName) { match in
                        GridRow {
                            Text("\(match.style.family) \(match.style.style)")
                            Text(AppModel.versionNumber(match.style.version) ?? "Unknown").foregroundStyle(.secondary)
                            libraryText(match)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
        }
    }

    private var stylesSummary: String {
        let families = Set(matches.compactMap(\.family?.id))
        guard families.count == 1, let family = matches.compactMap(\.family).first else {
            return matches.count == 1 ? "1 style" : "\(matches.count.plain) styles"
        }
        let covered = model.coveredFaces(of: family, by: license).count
        return covered == family.faces.count
            ? "All \(family.faces.count.plain) styles of \(family.name) in your library"
            : "\(covered.plain) of the \(family.faces.count.plain) styles of \(family.name) in your library"
    }

    @ViewBuilder
    private func libraryText(_ match: LicenseMatch) -> some View {
        if let face = match.face {
            let mine = AppModel.versionNumber(match.style.version)
            let theirs = AppModel.versionNumber(face.face.version)
            if let mine, let theirs, mine != theirs {
                let newer = theirs.compare(mine, options: .numeric) == .orderedDescending
                Label(newer ? "Has \(theirs), a newer version" : "Has \(theirs), an older version", systemImage: "circle.fill")
                    .labelStyle(DotLabelStyle(color: .orange))
            } else {
                Label("Same version", systemImage: "circle.fill").labelStyle(DotLabelStyle(color: .green))
            }
        } else {
            Text("Not in your library").foregroundStyle(.secondary)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Files").font(.headline)
                Text(files.count == 1 ? "1 file" : "\(files.count.plain) files").foregroundStyle(.secondary)
                Spacer()
                Button("Add Files…") { addFiles() }
            }
            VStack(spacing: 0) {
                ForEach(files) { file in
                    FileRow(file: file, url: license.folder.appendingPathComponent(file.path)) {
                        previewed = license.folder.appendingPathComponent(file.path)
                    } reveal: {
                        model.showInFinder(license, file: file)
                    }
                    if file.id != files.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose files to copy into “\(license.name)”. The originals stay where they are."
        guard panel.runModal() == .OK else { return }
        save()
        model.addFiles(panel.urls, to: license)
    }

    static func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private struct StoredKey: Equatable {
    let license: VaultLicense?
    let revision: Int
}

private struct DotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

private struct FileRow: View {
    let file: VaultFile
    let url: URL
    let preview: () -> Void
    let reveal: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(kindText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isHovered {
                Button("Quick Look", action: preview).controlSize(.small)
                Button("Show in Finder", action: reveal).controlSize(.small)
            }
            Text(file.size.formatted(.byteCount(style: .file)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Quick Look", action: preview)
            Button("Show in Finder", action: reveal)
        }
    }

    private var kindText: String {
        let folder = (file.path as NSString).deletingLastPathComponent
        let kind = switch file.kind {
        case .font: "Font"
        case .webFont: "Web font"
        case .document: "Document"
        case .archive: "ZIP file"
        case .other: "File"
        }
        return folder.isEmpty ? kind : "\(kind) in \(folder)"
    }
}

struct OwnerField: View {
    @Binding var owner: String
    let owners: [String]

    var body: some View {
        HStack(spacing: 4) {
            TextField("Owner", text: $owner, prompt: Text("Me, or a client’s name"))
            if !owners.isEmpty {
                Menu {
                    ForEach(owners, id: \.self) { name in
                        Button(name) { owner = name }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose an owner you used before")
            }
        }
    }
}

struct KindToggles: View {
    @Binding var kinds: [VaultLicense.Kind]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(VaultLicense.Kind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { kinds.contains(kind) },
                    set: { isOn in
                        var set = Set(kinds)
                        if isOn { set.insert(kind) } else { set.remove(kind) }
                        kinds = VaultLicense.Kind.allCases.filter(set.contains)
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Add sheet

struct VaultAddSheet: View {
    @Environment(AppModel.self) private var model
    let prompt: VaultAddPrompt
    @State private var owner = ""
    @State private var name: String
    @State private var kinds: [VaultLicense.Kind]
    @State private var project = ""
    @State private var endsOn = false
    @State private var ends = Date.now

    init(prompt: VaultAddPrompt) {
        self.prompt = prompt
        _name = State(initialValue: prompt.draft.suggestedName)
        _kinds = State(initialValue: prompt.draft.kinds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to the Vault").font(.title2.bold())
                Text("Cicero copies these files into the Vault. The originals stay where they are.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: prompt.draft.unpackedArchives.isEmpty ? "doc.on.doc" : "doc.zipper")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sourceTitle).lineLimit(1).truncationMode(.middle)
                    Text(sourceDetail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            Form {
                OwnerField(owner: $owner, owners: model.vaultOwners)
                TextField("Name", text: $name)
                LabeledContent("Kind") { KindToggles(kinds: $kinds) }
                TextField("Project or domain", text: $project, prompt: Text("Optional"))
                LabeledContent("Ends") {
                    HStack {
                        Toggle("Ends", isOn: $endsOn).labelsHidden()
                        DatePicker("Ends", selection: $ends, displayedComponents: .date).labelsHidden().disabled(!endsOn)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
            .padding(.vertical, -12)
            VStack(alignment: .leading, spacing: 4) {
                Label(linkSummary, systemImage: prompt.draft.styles.isEmpty ? "info.circle" : "checkmark.circle.fill")
                    .foregroundStyle(prompt.draft.styles.isEmpty ? Color.secondary : Color.green)
                Text(filesSummary).font(.callout).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelAdding(prompt) }
                    .keyboardShortcut(.cancelAction)
                Button("Add to Vault") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed(owner).isEmpty || trimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let license = VaultLicense(owner: trimmed(owner), name: trimmed(name), kinds: kinds, project: trimmed(project),
                                   ends: endsOn ? ends : nil, added: .now)
        model.finishAdding(prompt, as: license)
    }

    private var sourceTitle: String {
        let sources = prompt.draft.sources
        return sources.count == 1 ? sources[0] : "\(sources.count.plain) items"
    }

    private var sourceDetail: String {
        let files = prompt.draft.files.count
        let count = files == 1 ? "1 file" : "\(files.plain) files"
        return prompt.draft.unpackedArchives.isEmpty ? count : "Unpacked: \(count)"
    }

    private var linkSummary: String {
        let styles = prompt.draft.styles
        guard !styles.isEmpty else { return "No fonts to link. You can add them later." }
        let probe = VaultLicense(owner: "", name: "", styles: styles)
        let matches = model.matches(for: probe)
        let inLibrary = matches.count { $0.face != nil }
        let families = Set(styles.map { AppModel.withoutWeb($0.family) })
        let what = families.count == 1
            ? "\(styles.count == 1 ? "1 style" : "\(styles.count.plain) styles") of \(families.first!)"
            : "\(styles.count.plain) styles of \(families.count.plain) families"
        let library = inLibrary == matches.count ? (matches.count == 1 ? "It’s in your library." : "All are in your library.")
            : inLibrary == 0 ? "None are in your library." : "\(inLibrary.plain) are in your library."
        return "Linked to \(what). \(library)"
    }

    private var filesSummary: String {
        let files = prompt.draft.files
        var parts: [String] = []
        func add(_ kind: VaultFile.Kind, _ one: String, _ many: String) {
            let count = files.count { $0.kind == kind }
            if count > 0 { parts.append(count == 1 ? "1 \(one)" : "\(count.plain) \(many)") }
        }
        add(.font, "font", "fonts")
        add(.webFont, "web font", "web fonts")
        add(.document, "document", "documents")
        add(.archive, "ZIP file", "ZIP files")
        add(.other, "other file", "other files")
        return parts.listed()
    }
}
