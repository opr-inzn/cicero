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
        } detail: {
            // A stack in a split view's detail column swaps the whole column for a page pushed onto it, dropping
            // whatever is around the stack: each page makes room for the Info panel and takes dropped files.
            NavigationStack(path: Binding(
                get: { model.openFamilyID.map { [$0] } ?? [] },
                set: { model.openFamilyID = $0.last }
            )) {
                BrowserView()
                    .modifier(DetailPage())
                    .navigationDestination(for: String.self) { FontPage(familyID: $0).modifier(DetailPage()) }
            }
        }
        // Over the split view, so the panel stays put when a font page opens or closes.
        .modifier(InfoPanelOverlay())
        .background { QuickLookHost() }
        // While the Fonts in Document sheet is up, it asks how to activate itself: a window shows one sheet.
        .sheet(item: Binding(get: { model.documentFonts == nil ? model.activationPrompt : nil }, set: { model.activationPrompt = $0 })) {
            ActivationSheet(prompt: $0)
        }
        .sheet(item: $model.documentFonts) { DocumentFontsSheet(report: $0) }
        .fontCacheSheet(isPresented: $model.isClearingCaches)
        .sheet(item: $model.editingSmartSet) { SmartSetEditor(original: $0) }
        .sheet(item: $model.editingCharacterSet) { CharacterSetEditor(original: $0) }
        .sheet(isPresented: Binding(get: { model.editingAppsForSet != nil }, set: { if !$0 { model.editingAppsForSet = nil } })) {
            if let id = model.editingAppsForSet { AppSetEditor(setID: id) }
        }
        .backupSheet(isPresented: $backup.isBackingUp)
        .restoreSheet(contents: $backup.restoring)
        .alert(
            "Deactivate fonts?",
            isPresented: Binding(get: { model.deactivationPrompt != nil }, set: { if !$0 { model.deactivationPrompt = nil } }),
            presenting: model.deactivationPrompt
        ) { prompt in
            Button("Deactivate") { model.performDeactivation(prompt.faces) }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.unmanagedCount == 1
                ? "1 file wasn’t installed by Cicero, so it may be your only copy. Cicero will move it to its Deactivated folder, which stays in your library."
                : "\(prompt.unmanagedCount) files weren’t installed by Cicero, so they may be your only copies. Cicero will move them to its Deactivated folder, which stays in your library.")
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
            if let toast = model.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.toast)
    }

    static func trashMessage(_ plan: TrashPlan) -> String {
        var parts = [plan.paths.count == 1
            ? "1 font file will be removed from your Mac and turned off in every app."
            : "\(plan.paths.count) font files\(plan.includesCopies ? ", including copies in other folders," : "") will be removed from your Mac and turned off in every app."]
        if !plan.otherFamilies.isEmpty {
            let names = ListFormatter.localizedString(byJoining: Array(plan.otherFamilies.prefix(3))) + (plan.otherFamilies.count > 3 ? " and others" : "")
            if plan.spareCopiesOf != nil {
                // Problems only removes files whose every font has a copy elsewhere.
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

/// A page of the detail column: room for the Info panel, and files dropped on it.
private struct DetailPage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(InfoPanelInset())
            .modifier(FileDrop())
    }
}

/// Font files and folders dropped from the Finder onto the browser or a font page join the library, and the
/// set the browser shows when it shows one. The page is outlined while files are over it.
private struct FileDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                isTargeted = false
                model.open(urls, into: set)
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                // From outside Cicero: families dragged within the window are names, not files.
                case .entering, .active: isTargeted = session.localSession == nil
                default: isTargeted = false
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The set the browser shows, which dropped fonts join.
    private var set: UUID? {
        guard model.openFamilyID == nil, model.selectedItems.count == 1, case .set(let id) = model.selection else { return nil }
        return id
    }
}
