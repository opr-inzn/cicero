import CiceroCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var promptText = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: SidebarWidth.minimum, ideal: SidebarWidth.ideal, max: SidebarWidth.maximum)
                .background { SidebarItemReader() }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { SidebarRoom.shared.sidebar = $0 }
        } detail: {
            // A stack in a split view's detail column swaps the whole column for a page pushed onto it, dropping whatever is around the stack: each page makes room for the Info panel and takes dropped files.
            NavigationStack(path: Binding(
                get: { model.openFamilyID.map { [$0] } ?? [] },
                set: { model.openFamilyID = $0.last }
            )) {
                BrowserView()
                    // Here rather than in BrowserView, so switching its view doesn't make the toolbar again.
                    .toolbar { BrowserToolbar() }
                    .modifier(DetailPage(isCovered: model.openFamilyID != nil))
                    // A page of its own for each family, so one opened from another's starts at the top rather than scrolled where the other was.
                    .navigationDestination(for: String.self) { FontPage(familyID: $0).id($0).modifier(DetailPage()) }
            }
            .transaction(value: model.openFamilyID) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { SidebarRoom.shared.detailStart = $0 }
        }
        // On the split view: on the stack, the search field doesn't show at all.
        .searchable(text: searchText, tokens: searchTokens, placement: .toolbar, prompt: "Search", token: tokenLabel)
        .searchSuggestions { SearchSuggestions() }
        .toolbarGlassFollowsAppearance()
        .modifier(InfoPanelOverlay())
        .background { QuickLookHost() }
        .background { WindowReader { TextEditingKeys.mainWindow = $0 } }
        .task(id: model.mayOfferEarlierImportCopy || model.earlierImportPrompt != nil) {
            guard !model.mayOfferEarlierImportCopy, model.earlierImportPrompt == nil, WhatsNew.shared.takePending() else { return }
            openWindow(id: WindowID.whatsNew)
        }
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
        .backupSheet(isPresented: $model.showsBackupSheet)
        .restoreSheet(contents: $model.restorePrompt)
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
            let named = shown.listed()
            Text("The file that turns off also holds \(named). \(styles.count == 1 ? "It turns" : "They turn") off too.")
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
        .alert("Classify Your Fonts Automatically?", isPresented: Binding(get: { model.showsGuessingQuestion }, set: { _ in })) {
            // Side by side only with short titles: a longer one, like Don't Classify, makes the alert stack the buttons.
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
                .disabled(prompt.requiresText && promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: model.textPrompt?.id) { promptText = model.textPrompt?.initialText ?? "" }
        .overlay(alignment: .bottom) {
            // Animated in here only: on the window, everything that changed with a toast would slide into place too.
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
            let names = plan.otherFamilies.count > 3 ? plan.otherFamilies.prefix(3).joined(separator: ", ") + " and others" : plan.otherFamilies.listed()
            if plan.spareCopiesOf != nil {
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
                Button("Choose for Each") { model.ask { $0.duplicatePrompt = prompt } }
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

    static func openAppsTitle(_ prompt: OpenAppsReplacePrompt) -> String {
        "Replace Fonts While \(prompt.apps.listed()) \(prompt.apps.count == 1 ? "Is" : "Are") Open?"
    }

    static func openAppsMessage(_ prompt: OpenAppsReplacePrompt) -> String {
        prompt.apps.count == 1
            ? "\(prompt.apps[0]) keeps the old version until it restarts, and documents open in it can show wrong letters. Quit it first, or restart it afterwards."
            : "\(prompt.apps.listed()) keep the old version until they restart, and documents open in them can show wrong letters. Quit them first, or restart them afterwards."
    }

    private func replaceTitle(_ prompt: DuplicatePrompt) -> String {
        let warned = prompt.duplicates.filter(model.warnsBeforeReplacing)
        guard warned.count == 1 else {
            return warned.allSatisfy(\.replacesSeveralCopies) ? "Replace Fonts in More Than One Place?" : "Replace These Fonts?"
        }
        let one = warned[0]
        return one.replacesSeveralCopies ? "Replace \(one.family) in \(one.replacements.count) Places?"
            : "Replace \(one.family) \(model.replacedPlaces(one))?"
    }

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
        let spares = spare.reduce(0) { $0 + $1.1 } == 1
            ? "Cicero’s copy of \(families[0]) in your Fonts folder only goes to the Trash, as the added one in Cicero’s Library takes over."
            : "Cicero’s copies of \(families.listed()) in your Fonts folder only go to the Trash, as the added ones in Cicero’s Library take over."
        return (lines + ["Each of these files goes to the Trash, and the added one takes its place.", spares]).joined(separator: " ")
    }
}

private struct DetailPage: ViewModifier {
    var isCovered = false

    func body(content: Content) -> some View {
        content
            .modifier(CoveredSize(isCovered: isCovered))
            .environment(\.isCovered, isCovered)
            .modifier(InfoPanelInset(isCovered: isCovered))
            .modifier(FileDrop())
    }
}

private struct CoveredSize: ViewModifier {
    let isCovered: Bool
    @State private var size: CGSize?

    func body(content: Content) -> some View {
        content
            .frame(width: isCovered ? size?.width : nil, height: isCovered ? size?.height : nil, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [isCovered] in if !isCovered { size = $0 } }
            // Not clipped: the browser scrolls under the toolbar's glass, and while it's covered nothing of it shows.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension EnvironmentValues {
    @Entry var isCovered = false
}

private struct FileDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .outsideFileDrops(isOver: { isTargeted = $0 }) { urls in
                isTargeted = false
                // A glyph dragged off a font page and let go over it again: macOS 15 doesn't say the drag is Cicero's own, so its file is left out.
                let urls = urls.filter { !GlyphVectors.isDragFile($0) }
                guard !urls.isEmpty else { return }
                model.open(urls, into: model.targetForAddedFiles)
            }
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

