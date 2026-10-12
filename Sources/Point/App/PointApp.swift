import SwiftUI

@main
struct PointApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        Window("Point", id: "main") {
            RootView()
                .environment(library)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { library.start() }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { PointCommands(library: library) }

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

struct PointCommands: Commands {
    let library: LibraryStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Folder…") { library.presentAddFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("New Collection…") {
                library.prompt("New Collection", confirm: "Create") { library.addCollection(named: $0, with: library.selectedFamilies) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Reveal in Finder") { library.revealSelection() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Show Info") { library.toggleInfo() }
                .keyboardShortcut("i", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button(library.isEditingSidebar ? "Done Editing Sidebar" : "Edit Sidebar") {
                withAnimation(.snappy) { library.isEditingSidebar.toggle() }
            }
            Button("Rescan Library") { library.rescan() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(Prefs.colorMode) private var colorMode: PreviewColorMode = .light
    @AppStorage(Prefs.customForeground) private var customForeground = "#FFFFFF"
    @AppStorage(Prefs.customBackground) private var customBackground = "#F04000"
    @State private var promptText = ""

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 340)
                .environment(\.colorScheme, library.systemColorScheme)
                .background(SidebarAppearance(colorScheme: library.systemColorScheme))
        } detail: {
            Group {
                if let family = library.detailFamily {
                    FamilyDetailView(family: family)
                } else {
                    BrowserView()
                }
            }
            .inspector(isPresented: $library.isInspectorPresented) {
                InspectorPanel()
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
        }
        // The title bar and toolbar sit over the canvas, so the window takes the canvas's light/dark scheme.
        .preferredColorScheme(PreviewColors(mode: colorMode, foregroundHex: customForeground, backgroundHex: customBackground).colorScheme)
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
            Text("\(request.unmanagedCount == 1 ? "1 file wasn't" : "\(request.unmanagedCount) files weren't") installed by Point, so there may be no other copy. Point will move \(request.unmanagedCount == 1 ? "it" : "them") to its Deactivated folder, which stays in your library.")
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
            Toggle("Remember this choice (you can change it in Settings)", isOn: $remember)
                .toggleStyle(.checkbox)
            HStack {
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
