import CiceroCore
import SwiftUI

/// What another font manager's library has, to pick what comes over: FontExplorer X's Font Library and other fonts, its
/// sets, application sets and smart sets, labels (as tags), classifications, ratings, comments (as notes), activation
/// history and the fonts that were on; Font Book's collections; or FontBase's folder, collections, tags and the fonts
/// that were on. Then progress while it's brought in, and what came over. A library its app writes to while it's open
/// waits for the app to quit, and is read again then.
struct ImportSheet: View {
    @State private var prompt: ImportPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choices: ImportChoices
    @State private var stage: ImportStage?
    @State private var task: Task<Void, Never>?
    @State private var summary: ImportSummary?
    /// The other app is open, so its library can't be imported yet.
    @State private var appIsOpen = false
    /// Reading the library again, as the app left it on quitting.
    @State private var isRereading = false
    /// The choices' height, and the header's, to fit the sheet to them.
    @State private var contentHeight: CGFloat?
    @State private var headerHeight: CGFloat = 0

    init(prompt: ImportPrompt) {
        _prompt = State(initialValue: prompt)
        _choices = State(initialValue: ImportChoices(for: prompt.library))
    }

    private var library: ImportedLibrary { prompt.library }
    private var appName: String { prompt.source.appName }

    var body: some View {
        VStack(spacing: 0) {
            if let summary {
                result(summary)
            } else {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { sections }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                // As tall as what's in it, up to the sheet's 640 points, so nothing is left empty below the last line.
                .frame(height: contentHeight.map { min($0, 640 - headerHeight - 70) })
                .disabled(stage != nil)
                Divider()
                footer
            }
        }
        .frame(width: 600)
        .onAppear { appIsOpen = isAppRunning }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { note in
            if isOtherApp(note) { appIsOpen = isAppRunning }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { note in
            guard isOtherApp(note) else { return }
            appIsOpen = isAppRunning
            if !appIsOpen { reread() }
        }
    }

    // MARK: Waiting for the other app

    /// The app whose library this is, when it writes to it while open: FontBase's bundle ID.
    private var waitsForBundleID: String? {
        prompt.waitsForQuit && prompt.source == .fontBase ? FontBaseImport.bundleIdentifier : nil
    }

    private var isAppRunning: Bool {
        guard let bundleID = waitsForBundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func isOtherApp(_ note: Notification) -> Bool {
        guard let bundleID = waitsForBundleID else { return false }
        return (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
    }

    private var isWaiting: Bool { appIsOpen || isRereading }

    /// Reads the library as the app left it, keeping what the user chose: what's new is chosen as it would be at first.
    private func reread() {
        isRereading = true
        Task {
            defer { isRereading = false }
            guard let fresh = await model.reread(prompt) else { return }
            let before = prompt.library
            let defaults = ImportChoices(for: fresh.library)
            let oldSets = Set(before.sets.map(\.id))
            choices.sets = choices.sets.intersection(fresh.library.sets.map(\.id)).union(defaults.sets.subtracting(oldSets))
            if before.active.isEmpty { choices.activate = defaults.activate }
            prompt = fresh
        }
    }

    private var quitBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quit \(appName) to import").bold()
                Text("\(appName) saves its library as it quits. Cicero reads it again then, and you can import.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Quit \(appName)") {
                guard let bundleID = waitsForBundleID else { return }
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Choosing

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Import from \(appName)").font(.title2.bold())
            HStack(spacing: 6) {
                Text(prompt.origin).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choose Another") { model.chooseImportFile(for: prompt.source) }
                    .buttonStyle(.link)
                    .disabled(stage != nil)
            }
            if appIsOpen { quitBanner.padding(.top, 10) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    /// What the other app calls the folder its fonts are in.
    private var fontFolderTitle: String {
        prompt.source == .fontBase ? "FontBase’s folder" : "Font Library"
    }

    @ViewBuilder
    private var sections: some View {
        if library.fontFolder != nil || !library.otherFiles.isEmpty {
            section("Fonts") {
                if let folder = library.fontFolder {
                    checkbox(fontFolderTitle, detail: fontLibraryDetail(folder), isOn: $choices.fontFolder)
                }
                if !library.otherFiles.isEmpty {
                    checkbox("Fonts in other folders", detail: otherFilesDetail, isOn: $choices.otherFiles)
                }
            }
        }
        let plain = library.sets.filter { !$0.isApplicationSet }
        if !plain.isEmpty {
            section(prompt.source == .fontExplorer ? "Sets" : "Collections", selecting: plain.map(\.id), in: \.sets) {
                ForEach(plain) { set in checkbox(set.name, detail: detail(set), isOn: member(set.id, of: \.sets)) }
            }
        }
        let applicationSets = library.sets.filter(\.isApplicationSet)
        if !applicationSets.isEmpty {
            section("Application Sets", selecting: applicationSets.map(\.id), in: \.sets) {
                ForEach(applicationSets) { set in checkbox(set.name, detail: detail(set), isOn: member(set.id, of: \.sets)) }
            }
        }
        if !library.smartSets.isEmpty {
            section("Smart Sets", selecting: library.smartSets.filter(\.unsupported.isEmpty).map(\.id), in: \.smartSets) {
                ForEach(library.smartSets) { smart in
                    if smart.unsupported.isEmpty {
                        checkbox(smart.name, detail: rulesDetail(smart), isOn: member(smart.id, of: \.smartSets))
                    } else {
                        checkbox(smart.name, detail: "Cicero has no rule for \(smart.unsupported.formatted(.list(type: .and))).",
                                 isOn: .constant(false))
                            .disabled(true)
                    }
                }
            }
        }
        if !library.tags.isEmpty || !library.classifications.isEmpty || !library.ratings.isEmpty || !library.comments.isEmpty
            || !library.history.isEmpty || !library.active.isEmpty {
            section(prompt.source == .fontBase ? "Tags and Activations" : "Tags, Classifications, Ratings and Activations") {
                if !library.tags.isEmpty, prompt.source == .fontBase {
                    checkbox("Tags", detail: "\(library.tags.map(\.name).formatted(.list(type: .and))), given to each family whose styles have the tag.",
                             isOn: $choices.tags)
                } else if !library.tags.isEmpty {
                    checkbox("Labels as tags", detail: "\(library.tags.map(\.name).formatted(.list(type: .and))), given to each family whose styles have the label.",
                             isOn: $choices.tags)
                }
                if !library.classifications.isEmpty {
                    checkbox("Classifications", detail: classificationsDetail, isOn: $choices.classifications)
                }
                if !library.ratings.isEmpty {
                    checkbox("Ratings", detail: "\(count(library.ratings.count, "rated style")). A family gets its best style’s stars, unless it has a rating already.",
                             isOn: $choices.ratings)
                }
                if !library.comments.isEmpty {
                    checkbox("Comments as notes", detail: "\(count(library.comments.count, "comment")), each in its family’s note, unless the family has a note already.",
                             isOn: $choices.comments)
                }
                if !library.history.isEmpty {
                    checkbox("Activation history", detail: "How often each family was activated, and when last, for the Times Activated and Last Activated rules.",
                             isOn: $choices.history)
                }
                if !library.active.isEmpty {
                    // FontBase's own library can't be imported until it has quit, so it can't turn them off again.
                    let quit = prompt.waitsForQuit ? "" : " Quit \(appName) first, so it doesn’t deactivate them again."
                    checkbox("Activate the fonts that were active", detail: "\(count(library.active.count, "style")), activated where they are." + quit,
                             isOn: $choices.activate)
                }
                // While the app is open its copies are its own: it deletes them as it quits, unless it's set not to. So
                // they're only offered once the library has been read again after it quit.
                if !library.leftoverCopies.isEmpty, !isWaiting {
                    checkbox("Remove \(appName)’s copies", detail: "\(count(library.leftoverCopies.count, "copy", "copies")) it left in "
                        + "\(commonFolder(library.leftoverCopies)), to the Trash, so those fonts aren’t on twice.",
                             isOn: $choices.removeCopies)
                }
            }
        }
        if !library.notes.isEmpty {
            section("Not Imported") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(library.notes, id: \.self) { note in
                        Label { Text(note.prefix(1).uppercased() + note.dropFirst()).fixedSize(horizontal: false, vertical: true) }
                            icon: { Image(systemName: "circle.fill").font(.system(size: 5)) }
                            .labelStyle(BulletLabelStyle())
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 2)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let stage {
                progress(stage)
            } else if isRereading {
                ProgressView().controlSize(.small)
                Text("Reading \(appName)’s library").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Your current setup is saved first, in Backups.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            // While fonts are copied, the task closes the sheet once it has stopped: closing it discards the unzipped
            // backup, which a copy may still be reading. Once they're listed, the rest goes through.
            Button("Cancel", role: .cancel) {
                if let task { task.cancel() } else { dismiss() }
            }
            .disabled(stage != nil && !isCopying)
            Button("Import") { start() }
                .keyboardShortcut(.defaultAction)
                .disabled(stage != nil || !hasChoice || isWaiting)
        }
        .padding(16)
    }

    @ViewBuilder
    private func progress(_ stage: ImportStage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch stage {
            case .copying(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Putting fonts in the Font Library, \(done.formatted()) of \(total.formatted())")
            case .reading(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Reading fonts, \(done.formatted()) of \(total.formatted())")
            case .starting:
                ProgressView()
                Text("Importing")
            }
        }
        .progressViewStyle(.linear)
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(maxWidth: 300, alignment: .leading)
    }

    private var isCopying: Bool {
        if case .copying = stage { true } else { false }
    }

    private func start() {
        stage = .starting
        let choices = choices
        task = Task {
            let result = await model.performImport(prompt, choices: choices) { stage in
                Task { @MainActor in if self.summary == nil { self.stage = stage } }
            }
            task = nil
            guard let result else { return dismiss() }
            summary = result
        }
    }

    // MARK: Rows

    private func section<Content: View>(_ title: String, selecting ids: [String] = [], in keyPath: WritableKeyPath<ImportChoices, Set<String>>? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let keyPath, ids.count > 1 {
                    let all = ids.allSatisfy(choices[keyPath: keyPath].contains)
                    Button(all ? "Deselect All" : "Select All") {
                        if all { choices[keyPath: keyPath].subtract(ids) } else { choices[keyPath: keyPath].formUnion(ids) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            .padding(.horizontal, 20)
            content()
        }
    }

    private func checkbox(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 20)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func member(_ id: String, of keyPath: WritableKeyPath<ImportChoices, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { choices[keyPath: keyPath].contains(id) },
            set: { isOn in
                if isOn { choices[keyPath: keyPath].insert(id) } else { choices[keyPath: keyPath].remove(id) }
            }
        )
    }

    /// Enough for every section and row, before it scrolls: the title and the buttons, each section's title and the
    /// space after it, each row's two lines, and the line about what isn't imported.
    private var hasChoice: Bool {
        (choices.fontFolder && library.fontFolder != nil) || (choices.otherFiles && !library.otherFiles.isEmpty)
            || !choices.sets.isEmpty || !choices.smartSets.isEmpty
            || (choices.tags && !library.tags.isEmpty) || (choices.classifications && !library.classifications.isEmpty)
            || (choices.ratings && !library.ratings.isEmpty) || (choices.comments && !library.comments.isEmpty)
            || (choices.history && !library.history.isEmpty) || (choices.activate && !library.active.isEmpty)
    }

    private var classificationsDetail: String {
        let own = Array(Set(library.classifications.filter { $0.builtIn == nil }.map(\.name))).sorted()
        let yours = own.isEmpty ? "" : " Your own, \(own.map { "“\($0)”" }.formatted(.list(type: .and))), come along."
        return "\(count(library.classifications.count, "classified style")). A family goes in the classification most of its styles have, "
            + "unless you’ve chosen one for it." + yours
    }

    /// The folder the files are in, "~/Library/Fonts/FontBase", or the first one's.
    private func commonFolder(_ paths: [String]) -> String {
        let folders = paths.map { ($0 as NSString).deletingLastPathComponent }
        return ((folders.first ?? "") as NSString).abbreviatingWithTildeInPath
    }

    private func fontLibraryDetail(_ folder: String) -> String {
        let place = (folder as NSString).abbreviatingWithTildeInPath
        if let bundled = library.bundledFonts {
            return "\(place) (\(count(bundled.files.count, "font file")) from the backup)"
        }
        return "\(place) (\(count(library.fontFolderCount, "font file")))"
    }

    /// The folders the other files are in, those with the most first, then how many there are: "~/Desktop/Client and
    /// ~/Documents/Fonts (3 font files)", "~/Desktop/Client, ~/Documents/Fonts and 4 other folders (40 font files)".
    private var otherFilesDetail: String {
        let folders = Dictionary(grouping: library.otherFiles) { ($0 as NSString).deletingLastPathComponent }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { ($0.key as NSString).abbreviatingWithTildeInPath }
        let named = folders.count > 3 ? folders.prefix(2) + ["\(folders.count - 2) other folders"] : folders
        return "\(named.formatted(.list(type: .and))) (\(count(library.otherFiles.count, "font file")))"
    }

    /// "12 styles", "4 families and 2 styles", "For TextEdit · 3 styles", "Empty".
    private func detail(_ set: ImportedSet) -> String {
        var parts: [String] = []
        if !set.families.isEmpty { parts.append(count(set.families.count, "family", "families")) }
        if !set.fonts.isEmpty { parts.append(count(set.fonts.count, "style")) }
        let contents = parts.isEmpty ? "Empty" : parts.formatted(.list(type: .and))
        guard !set.apps.isEmpty else { return contents }
        let apps = set.apps.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        return "For \(apps.formatted(.list(type: .and))) · \(contents)"
    }

    private func rulesDetail(_ smart: ImportedSmartSet) -> String {
        switch smart.rules.count {
        case 0: "No rules"
        case 1: "1 rule"
        default: "\(smart.rules.count) rules, \(smart.matchAll ? "all" : "any") of them"
        }
    }

    private func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        number == 1 ? "1 \(singular)" : "\(number.formatted()) \(plural ?? singular + "s")"
    }

    // MARK: Done

    private func result(_ summary: ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Imported from \(appName)").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                ForEach(resultLines(summary), id: \.self) { line in
                    Label { Text(line).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)) }
                        .labelStyle(BulletLabelStyle())
                }
            }
            Text("Your setup from before is in ~/Library/Application Support/Cicero/Backups.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultLines(_ summary: ImportSummary) -> [String] {
        var lines: [String] = []
        let kinds: [(Int, String)] = [
            (summary.sets, "folder"), (summary.applicationSets, "app folder"),
            (summary.smartSets, "smart folder"), (summary.tags, "tag"),
        ]
        let made = kinds.filter { $0.0 > 0 }.map { count($0.0, $0.1) }
        if !made.isEmpty { lines.append(made.formatted(.list(type: .and)) + ".") }
        if summary.fonts > 0 { lines.append("\(count(summary.fonts, "font file")) listed in your library.") }
        if summary.activated > 0 {
            lines.append("\(count(summary.activated, "style")) activated, as they were in \(appName).")
            if prompt.source == .fontBase {
                lines.append("When FontBase opens, it activates them again, from copies of its own, so they’re on twice. Deactivate them in FontBase to stop that.")
            }
        }
        if summary.removedCopies > 0 {
            lines.append("\(count(summary.removedCopies, "copy", "copies")) \(appName) left in the Fonts folder moved to the Trash.")
        }
        if summary.ratedFamilies > 0 { lines.append("\(count(summary.ratedFamilies, "family", "families")) rated.") }
        if summary.classifiedFamilies > 0 { lines.append("\(count(summary.classifiedFamilies, "family", "families")) classified.") }
        if summary.notedFamilies > 0 {
            lines.append(summary.notedFamilies == 1 ? "1 family with a note from its comments." : "\(summary.notedFamilies.formatted()) families with notes from their comments.")
        }
        // Before what didn't come over: with nothing new, importing again says so first.
        if lines.isEmpty { lines.append("Nothing new: Cicero has all of it from before.") }
        if summary.notFound > 0 {
            let kinds = switch prompt.source {
            case .fontBook: "collections"
            case .fontBase: "collections, tags and active fonts"
            case .fontExplorer: "sets, tags, classifications and ratings"
            }
            lines.append("\(count(summary.notFound, "font")) in \(appName)’s \(kinds) \(summary.notFound == 1 ? "isn’t" : "aren’t") in your library.")
        }
        if !summary.emptySets.isEmpty {
            lines.append("Not imported: \(summary.emptySets.map { "“\($0)”" }.formatted(.list(type: .and))), as none of \(summary.emptySets.count == 1 ? "its" : "their") fonts are in your library.")
        }
        if !summary.skippedSmartSets.isEmpty {
            lines.append("Not imported: \(summary.skippedSmartSets.map { "“\($0)”" }.formatted(.list(type: .and))), whose rules name sets or labels that didn’t come along.")
        }
        if !summary.missingApps.isEmpty {
            lines.append("Not on this Mac, so their app folders are without them: \(summary.missingApps.formatted(.list(type: .and))).")
        }
        return lines
    }
}

/// A small bullet before each line.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(.secondary)
            configuration.title
        }
    }
}
