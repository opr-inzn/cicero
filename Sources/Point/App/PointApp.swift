import SwiftUI

@main
struct PointApp: App {
    @State private var library = LibraryStore()
    @State private var preview = PreviewSettings()

    var body: some Scene {
        Window("Point", id: "main") {
            RootView()
                .modifier(FontCacheDialogs(isConfirming: $library.isConfirmingCacheClear))
                .environment(library)
                .environment(preview)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    AppAppearance.applySaved()
                    library.start()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { PointCommands(library: library) }

        Window("Compare", id: PresentationWindow.compare) {
            CompareView()
                .environment(library)
                .environment(preview)
        }
        .defaultSize(width: 960, height: 640)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Window("Slideshow", id: PresentationWindow.slideshow) {
            SlideshowView()
                .environment(library)
                .environment(preview)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Window("Character Toolbox", id: "toolbox") {
            ToolboxWindow()
                .environment(library)
                .environment(preview)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { library.start() }
        }
        .defaultSize(width: 1000, height: 660)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

struct PointCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let library: LibraryStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Folder…") { library.presentAddFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("New Set…") {
                library.prompt("New Set", confirm: "Create") { library.addSet(named: $0, with: library.selectedFamilies) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Smart Set…") { library.editingSmartSet = SmartSet(name: "") }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .sidebar) {
            Button(library.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") {
                withAnimation(.snappy) { library.isEditingSidebar.toggle() }
            }
            Toggle("Show System Fonts", isOn: Binding(
                get: { library.data.showSystemFonts },
                set: { library.data.showSystemFonts = $0; library.save() }
            ))
            .keyboardShortcut(".", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Fonts") {
            let selection = library.selectedFamilies
            Button("Activate") { library.requestActivate(selection) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!selection.contains { $0.hasActivatableFaces || $0.hasTemporaryFaces })
            Menu("Activate Temporarily") {
                Button("Until Point Quits") { library.requestActivateTemporarily(selection, scope: .untilQuit) }
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                Button("Until You Log Out") { library.requestActivateTemporarily(selection, scope: .untilLogout) }
            }
            .disabled(!selection.contains(where: \.hasActivatableFaces))
            Button("Deactivate") { library.requestDeactivate(selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!selection.contains(where: \.hasDeactivatableFaces))
            Divider()
            Button("Show Info") { library.toggleInfo() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Reveal in Finder") { library.revealSelection() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(selection.isEmpty)
            Button("Move to Trash…") { library.requestTrash(selection) }
                .disabled(selection.isEmpty)
            Divider()
            PresentationCommands(library: library)
            Button("Character Toolbox") { openWindow(id: "toolbox") }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Rescan Library") { library.rescan() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Rebuild Font List") { library.rebuildFontList() }
            Button("Clear Font Caches…") { library.isConfirmingCacheClear = true }
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @State private var promptText = ""

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 340)
        } detail: {
            // The browser is the root; setting `detailFamilyID` pushes the font page and going back clears it.
            NavigationStack(path: Binding(
                get: { library.detailFamilyID.map { [$0] } ?? [] },
                set: { library.detailFamilyID = $0.last }
            )) {
                BrowserView()
                    .navigationDestination(for: String.self) { FontPage(familyID: $0) }
            }
        }
        .modifier(SetEditorSheets())
        .modifier(FontTrashAlert())
        .sheet(item: $library.pendingActivation) { request in
            ActivationSheet(request: request)
        }
        .alert(
            "Deactivate fonts?",
            isPresented: Binding(get: { library.pendingDeactivation != nil }, set: { if !$0 { library.pendingDeactivation = nil } }),
            presenting: library.pendingDeactivation
        ) { request in
            Button("Deactivate") { Task { await library.deactivate(request.faces) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("\(request.unmanagedCount == 1 ? "1 file wasn’t" : "\(request.unmanagedCount) files weren’t") installed by Point, so there may be no other copy. Point will move \(request.unmanagedCount == 1 ? "it" : "them") to its Deactivated folder, which stays in your library.")
        }
        .alert(
            library.textPrompt?.title ?? "",
            isPresented: Binding(get: { library.textPrompt != nil }, set: { if !$0 { library.textPrompt = nil } }),
            presenting: library.textPrompt
        ) { prompt in
            TextField("Name", text: $promptText)
            Button(prompt.confirmTitle) { prompt.action(promptText) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: library.textPrompt?.id) { promptText = library.textPrompt?.initialText ?? "" }
        .overlay(alignment: .bottom) {
            if let toast = library.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: library.toast)
    }
}

struct ActivationSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let request: ActivationRequest
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activate \(request.title)")
                .font(.headline)
            Text("Either way, the fonts turn on for every app.")
                .foregroundStyle(.secondary)
            option(.copy, icon: "doc.on.doc.fill", title: "Install a Copy",
                   detail: "Copies the files into ~/Library/Fonts, so they keep working if the originals move or their drive is unplugged.")
            option(.register, icon: "link.circle.fill", title: "Use Files Where They Are",
                   detail: "Nothing is copied. The fonts turn off if the original files move or go away.")
            Toggle("Remember this choice (you can change it in Settings → General)", isOn: $remember)
                .toggleStyle(.checkbox)
            HStack {
                // Session-only activation: used where they are, gone at quit or logout.
                TemporaryActivationMenu { scope in
                    let faces = request.faces
                    dismiss()
                    Task { await library.activateTemporarily(faces, scope: scope) }
                }
                .fixedSize()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func option(_ method: InstallMethod, icon: String, title: String, detail: String) -> some View {
        Button {
            if remember {
                library.data.installMethod = method
                library.save()
            }
            let faces = request.faces
            dismiss()
            Task { await library.activate(faces, method: method) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(.rect)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
