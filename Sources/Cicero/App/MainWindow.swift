import CiceroCore
import SwiftUI

/// Sidebar, the browser with font pages pushed over it, prompts and toasts.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(BackupPrompts.self) private var backup
    @State private var promptText = ""

    var body: some View {
        @Bindable var model = model
        @Bindable var backup = backup
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 340)
                // When it slides out and in, and where it is, for how much room hiding it gives the grid (see `SidebarRoom`).
                .background { SidebarItemReader() }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { SidebarRoom.shared.sidebar = $0 }
        } detail: {
            // A stack in a split view's detail column swaps the whole column for a page pushed onto it, dropping
            // whatever is around the stack: each page makes room for the Info panel and takes dropped files.
            NavigationStack(path: Binding(
                get: { model.openFamilyID.map { [$0] } ?? [] },
                set: { model.openFamilyID = $0.last }
            )) {
                BrowserView()
                    .modifier(DetailPage())
                    // A page of its own for each family, so one opened from another's, as from Similar, starts at the
                    // top, as from the browser, rather than scrolled where the other was.
                    .navigationDestination(for: String.self) { FontPage(familyID: $0).id($0).modifier(DetailPage()) }
            }
            // A font page appears and goes at once, never sliding in, whatever else is animating.
            .transaction(value: model.openFamilyID) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            // At the sidebar's edge, also while it slides in and out, which the grid follows (see `SidebarRoom`).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { SidebarRoom.shared.detailStart = $0 }
        }
        // On the split view, so font pages keep the field too (on the stack it doesn't show at all); typing in
        // it, or changing its tokens, on one goes back to the matches.
        .searchable(text: searchText, tokens: searchTokens, placement: .toolbar, prompt: "Search", token: tokenLabel)
        .searchSuggestions { SearchSuggestions() }
        // On the split view, so the browser and font pages both have it.
        .toolbarGlassFollowsAppearance()
        // Over the split view, so the panel stays put when a font page opens or closes.
        .modifier(InfoPanelOverlay())
        .background { QuickLookHost() }
        .background { WindowReader { TextEditingKeys.mainWindow = $0 } }
        // While the Fonts in Document sheet is up, it asks how to install itself: a window shows one sheet.
        .sheet(item: Binding(get: { model.documentFonts == nil ? model.installPrompt : nil }, set: { model.installPrompt = $0 })) {
            InstallSheet(prompt: $0)
        }
        .confirmsManyActivations(when: model.documentFonts == nil)
        .sheet(item: $model.documentFonts) { DocumentFontsSheet(report: $0) }
        // A sheet of its own for each library, rather than the last one's with its choices.
        .sheet(item: $model.importing) { ImportSheet(prompt: $0).id($0.id) }
        .sheet(item: $model.earlierImportPrompt) { EarlierImportSheet(prompt: $0) }
        .sheet(item: $model.duplicatePrompt) { DuplicatesSheet(prompt: $0) }
        .modifier(ReplaceAlerts())
        .fontCacheSheet(isPresented: $model.isClearingCaches)
        .sheet(item: $model.editingSmartSet) { SmartSetEditor(original: $0) }
        .sheet(item: $model.editingCharacterSet) { CharacterSetEditor(original: $0) }
        .confirmsCoverageSetDeletion($model.deletingCharacterSets)
        .sheet(item: $model.newTagRequest) { NewTagSheet(request: $0) }
        .sheet(isPresented: Binding(get: { model.editingAppsForSet != nil }, set: { if !$0 { model.editingAppsForSet = nil } })) {
            if let id = model.editingAppsForSet { AppSetEditor(setID: id) }
        }
        .backupSheet(isPresented: $backup.isBackingUp)
        .restoreSheet(contents: $backup.restoring)
        .alert(
            "Turn Off Other Styles Too?",
            isPresented: Binding(get: { model.copySwitchPrompt != nil }, set: { if !$0 { model.copySwitchPrompt = nil } }),
            presenting: model.copySwitchPrompt
        ) { request in
            Button("Use \(request.source)’s Copies") { model.confirmCopySwitch(request) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            let styles = request.plan.alsoTurnsOff
            let shown = styles.count > 6 ? Array(styles.prefix(5)) + ["\(styles.count - 5) more"] : styles
            let named = shown.count > 1 ? shown.dropLast().joined(separator: ", ") + " and " + shown.last! : shown.joined()
            Text("A file that goes off holds \(named) too. \(styles.count == 1 ? "It goes" : "They go") off with it.")
        }
        .alert(
            model.trashPlan.map { "Move \($0.title) to the Trash?" } ?? "",
            isPresented: Binding(get: { model.trashPlan != nil }, set: { if !$0 { model.trashPlan = nil } }),
            presenting: model.trashPlan
        ) { plan in
            Button("Move to Trash", role: .destructive) { model.moveToTrash(plan) }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(Self.trashMessage(plan))
        }
        // At the first launch, before anything is guessed.
        .alert("Classify Your Fonts Automatically?", isPresented: Binding(get: { model.asksAboutGuessing }, set: { _ in })) {
            // Side by side, Not Now in grey and Classify in the accent colour, the one Return chooses: a longer title, like
            // Don't Classify, and the alert stacks them.
            Button("Classify") { model.answerGuessing(true) }
                .keyboardShortcut(.defaultAction)
            Button("Not Now", role: .cancel) { model.answerGuessing(false) }
        } message: {
            Text("Many fonts don’t say whether they’re serif, sans serif, script or ornamental. Cicero can tell from the shapes of their letters" + (ClassificationGuesser.readsNames ? " and, with Apple Intelligence, from their names" : "") + ", on this Mac. Otherwise they stay Unclassified until you choose one. You can change this in Preferences → General.")
        }
        .alert(
            model.textPrompt?.title ?? "",
            isPresented: Binding(get: { model.textPrompt != nil }, set: { if !$0 { model.textPrompt = nil } }),
            presenting: model.textPrompt
        ) { prompt in
            TextField("Name", text: $promptText)
            Button(prompt.confirmTitle) { prompt.action(promptText) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: model.textPrompt?.id) { promptText = model.textPrompt?.initialText ?? "" }
        .overlay(alignment: .bottom) {
            // Animated in here only: on the window, everything that changed with a toast (fonts trashed, the
            // Info panel showing another) would slide into place too.
            ZStack {
                if let toast = model.toast {
                    HStack(spacing: 12) {
                        Text(toast)
                        if model.toastUndo != nil {
                            Button("Undo") { model.undoToast() }
                                .buttonStyle(.plain)
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glass(in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.toast)
        }
    }

    private var searchText: Binding<String> {
        Binding {
            model.searchText
        } set: { text in
            guard text != model.searchText else { return }
            model.searchText = text
            model.openFamilyID = nil
        }
    }

    private var searchTokens: Binding<[SearchToken]> {
        Binding {
            model.searchTokens
        } set: { tokens in
            guard tokens != model.searchTokens else { return }
            model.setSearchTokens(tokens)
            model.openFamilyID = nil
        }
    }

    private func tokenLabel(_ token: SearchToken) -> Text {
        Text(token.title)
    }

    static func trashMessage(_ plan: TrashPlan) -> String {
        var parts = [plan.paths.count == 1
            ? "1 font file will be removed from your Mac and turned off in every app."
            : "\(plan.paths.count) font files\(plan.includesCopies ? ", including copies in other folders," : "") will be removed from your Mac and turned off in every app."]
        if !plan.otherFamilies.isEmpty {
            let names = ListFormatter.localizedString(byJoining: Array(plan.otherFamilies.prefix(3))) + (plan.otherFamilies.count > 3 ? " and others" : "")
            if plan.spareCopiesOf != nil {
                // Conflicts only removes files whose every font has a copy elsewhere.
                let files = plan.paths.count == 1 ? "The file also contains" : "Some files also contain"
                let keep = plan.otherFamilies.count == 1 ? "which keeps its other copies" : "which keep their other copies"
                parts.append("\(files) \(names), \(keep).")
            } else {
                parts.append("Some files also contain \(names), which will be removed too.")
            }
        }
        if plan.protectedCount > 0 { parts.append("Files that come with macOS or an app stay where they are.") }
        parts.append(plan.paths.count == 1 ? "You can put it back from the Trash." : "You can put them back from the Trash.")
        return parts.joined(separator: " ")
    }
}

/// The questions before fonts are replaced: in more than one place or in the user's own folders (`replacePrompt`), and
/// while apps that keep a font's old version are open (`openAppsReplacePrompt`).
private struct ReplaceAlerts: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .alert(
                model.replacePrompt.map(replaceTitle) ?? "",
                isPresented: Binding(get: { model.replacePrompt != nil }, set: { if !$0 { model.replacePrompt = nil } }),
                presenting: model.replacePrompt
            ) { prompt in
                Button("Replace") { model.replaceEverywhere(prompt) }
                    .keyboardShortcut(.defaultAction)
                // Once the alert has gone, so the sheet isn't lost on its way out.
                Button("Choose for Each…") { Task { model.duplicatePrompt = prompt } }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                Text(replaceMessage(prompt))
            }
            .alert(
                model.openAppsReplacePrompt.map(Self.openAppsTitle) ?? "",
                isPresented: Binding(get: { model.openAppsReplacePrompt != nil }, set: { if !$0 { model.openAppsReplacePrompt = nil } }),
                presenting: model.openAppsReplacePrompt
            ) { prompt in
                Button("Replace") { prompt.replace(model) }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                Text(Self.openAppsMessage(prompt))
            }
    }

    /// "Replace Fonts While InDesign Is Open?", "…While InDesign and Photoshop Are Open?".
    static func openAppsTitle(_ prompt: OpenAppsReplacePrompt) -> String {
        "Replace Fonts While \(list(prompt.apps)) \(prompt.apps.count == 1 ? "Is" : "Are") Open?"
    }

    static func openAppsMessage(_ prompt: OpenAppsReplacePrompt) -> String {
        prompt.apps.count == 1
            ? "\(prompt.apps[0]) keeps the old version until it restarts, and documents open in it can show wrong letters. Quit it first, or restart it afterwards."
            : "\(list(prompt.apps)) keep the old version until they restart, and documents open in them can show wrong letters. Quit them first, or restart them afterwards."
    }

    /// "InDesign", "InDesign and Photoshop", "InDesign, Illustrator and Photoshop".
    static func list(_ names: [String]) -> String {
        names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.joined()
    }

    /// "Replace Helvetica in 2 Places?", "Replace Helvetica in Clients?", or for several families "Replace Fonts in More
    /// Than One Place?" or "Replace These Fonts?".
    private func replaceTitle(_ prompt: DuplicatePrompt) -> String {
        let warned = prompt.duplicates.filter(model.warnsBeforeReplacing)
        guard warned.count == 1 else {
            return warned.allSatisfy(\.replacesSeveralCopies) ? "Replace Fonts in More Than One Place?" : "Replace These Fonts?"
        }
        let one = warned[0]
        return one.replacesSeveralCopies ? "Replace \(one.family) in \(one.replacements.count) Places?"
            : "Replace \(one.family) \(model.replacedPlaces(one))?"
    }

    /// "Helvetica is in your Fonts folder and in Clients. Each of these files goes to the Trash, and the added one takes its place."
    /// For one file: "Helvetica is in Clients. The file goes to the Trash, and the added one takes its place."
    /// Cicero's copies that just go (see `AppModel.spareCopies`) are named: "…goes to the Trash. The added one takes the place
    /// of each, except Cicero’s copy of Helvetica in your Fonts folder: Helvetica is off, so the one in Cicero’s Library is
    /// enough."
    private func replaceMessage(_ prompt: DuplicatePrompt) -> String {
        let several = prompt.duplicates.filter(model.warnsBeforeReplacing)
        var lines = several.prefix(3).map { "\($0.family) is \(model.replacedPlaces($0))." }
        if several.count > 3 { lines.append("And \(several.count - 3) more.") }
        let spare = several.map { ($0.family, model.spareCopies($0).count) }.filter { $0.1 > 0 }
        guard !spare.isEmpty else {
            let files = several.reduce(0) { $0 + $1.replacements.count } == 1 ? "The file goes" : "Each of these files goes"
            return (lines + ["\(files) to the Trash, and the added one takes its place."]).joined(separator: " ")
        }
        let families = spare.map(\.0)
        let off = families.count == 1 ? "\(families[0]) is off" : "they’re off"
        let except = spare.reduce(0) { $0 + $1.1 } == 1
            ? "Cicero’s copy of \(families[0]) in your Fonts folder: \(off), so the one in Cicero’s Library is enough."
            : "Cicero’s copies of \(Self.list(families)) in your Fonts folder: \(off), so the ones in Cicero’s Library are enough."
        return (lines + ["Each of these files goes to the Trash. The added one takes the place of each, except " + except]).joined(separator: " ")
    }
}

/// A page of the detail column: room for the Info panel, and files dropped on it.
private struct DetailPage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(InfoPanelInset())
            .modifier(FileDrop())
    }
}

/// Font files and folders dropped from the Finder onto the browser or a font page, or copied there and pasted with ⌘V,
/// join the library, and the folder or tag the browser shows, or go into the location it shows (see
/// `AppModel.targetForAddedFiles`). The page is outlined while files are over it.
private struct FileDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            // From outside Cicero: families dragged within the window are names, not files.
            .drops(of: URL.self, fromOutsideOnly: true, isOver: { isTargeted = $0 }) { urls in
                isTargeted = false
                model.open(urls, into: model.targetForAddedFiles)
            }
            // While the grid, the list or the page has the focus; elsewhere `AppDelegate` takes ⌘V.
            .onPasteCommand(of: [.fileURL]) { _ in model.pasteFiles() }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
    }
}

