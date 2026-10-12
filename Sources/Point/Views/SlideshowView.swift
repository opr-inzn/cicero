import AppKit
import SwiftUI

/// Full-screen slideshow: one family at a time with the sample set huge in that font.
/// Arrow keys and space move, P plays, A activates or deactivates, Esc leaves.
struct SlideshowView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("slideshow.interval") private var interval = 5.0

    @State private var index = 0
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var hoveringControls = false
    @State private var idle = Idle()
    @State private var window: NSWindow?
    @State private var activation: ActivationRequest?
    @State private var deactivation: DeactivationRequest?
    @FocusState private var focused: Bool

    private static let intervals: [Double] = [2, 3, 5, 10, 20]

    private struct PlayKey: Equatable {
        var playing: Bool
        var interval: Double
    }

    /// Holds the hide-controls timer outside view state, so mouse moves don't redraw the slide.
    private final class Idle {
        var task: Task<Void, Never>?
    }

    var body: some View {
        let families = library.presentation.slideshowIDs.compactMap(library.family(named:))
        let current = families.isEmpty ? nil : families[min(index, families.count - 1)]
        ZStack {
            Color.canvas.ignoresSafeArea()
            if let current {
                slide(current)
                    .id(current.id)
                    .transition(.opacity)
            } else {
                ContentUnavailableView("Nothing to Show", systemImage: "play.rectangle",
                                       description: Text("Select fonts in the main window and choose Slideshow."))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current?.id)
        .overlay(alignment: .bottom) { controls(current, count: families.count) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1, in: families.count); return .handled }
        .onKeyPress(.rightArrow) { move(1, in: families.count); return .handled }
        .onKeyPress(.space) { move(1, in: families.count); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "aApP")) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            switch press.characters.lowercased() {
            case "a": if let current { toggleActivation(current) }
            case "p": isPlaying.toggle()
            default: return .ignored
            }
            wake()
            return .handled
        }
        .onExitCommand { close() }
        .onContinuousHover { phase in
            if case .active = phase { wake() }
        }
        .onChange(of: library.presentation.slideshowRun, initial: true) {
            index = library.presentation.slideshowStart
            isPlaying = false
        }
        .task(id: PlayKey(playing: isPlaying, interval: interval)) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                move(1, in: families.count, wrapping: true)
            }
        }
        .background(WindowAccessor(configure: configure))
        .onAppear {
            focused = true
            wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window, notification.object as? NSWindow === window { focused = true }
        }
        .sheet(item: $activation) { ActivationSheet(request: $0) }
        .alert(
            "Deactivate fonts?",
            isPresented: Binding(get: { deactivation != nil }, set: { if !$0 { deactivation = nil } }),
            presenting: deactivation
        ) { request in
            Button("Deactivate") { Task { await library.deactivate(request.faces) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("\(request.unmanagedCount == 1 ? "1 file wasn't" : "\(request.unmanagedCount) files weren't") installed by Point, so there may be no other copy. Point will move \(request.unmanagedCount == 1 ? "it" : "them") to its Deactivated folder, which stays in your library.")
        }
    }

    // MARK: Slide

    private func slide(_ family: FontFamily) -> some View {
        let face = family.face(nearestWeight: Int(preview.weight))
        return GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(family.name)
                        .font(.title.weight(.semibold))
                    Text(summary(of: family))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 24)
                Text(preview.text(for: family))
                    .font(Font(FontCache.shared.font(face.face, size: geometry.size.height / 5, weight: preview.weight)))
                    .kerning(preview.kerning(atSize: geometry.size.height / 5))
                    .lineLimit(4)
                    .minimumScaleFactor(0.1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 24)
                if family.faces.count > 1 {
                    FlowLayout(spacing: 18, lineSpacing: 6) {
                        ForEach(family.faces.prefix(12)) { style in
                            Text(style.face.styleName)
                                .font(Font(FontCache.shared.font(style.face, size: 18)))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if family.faces.count > 12 {
                            Text("+\(family.faces.count - 12) more").font(.callout).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.bottom, 72)
                }
            }
            .padding(.horizontal, 72)
            .padding(.top, 56)
            .padding(.bottom, 24)
        }
    }

    private func summary(of family: FontFamily) -> String {
        var parts: [String] = []
        if let foundry = library.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.stylesLabel)
        switch family.status {
        case .active: parts.append("Activated")
        case .partial: parts.append("\(family.activeFaceCount) activated")
        case .system: parts.append("Installed with macOS")
        case .appOnly(let app): parts.append("Active in \(app) apps")
        case .inactive: parts.append("Not activated")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ current: FontFamily?, count: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                control("chevron.left", help: "Previous (←)") { move(-1, in: count) }
                control(isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause (P)" : "Play (P)") { isPlaying.toggle() }
                control("chevron.right", help: "Next (→ or Space)") { move(1, in: count) }
                Text("\(count == 0 ? 0 : min(index, count - 1) + 1) of \(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                Menu {
                    Picker("Interval", selection: $interval) {
                        ForEach(Self.intervals, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("\(Int(interval)) s", systemImage: "timer")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("How long each font stays when playing")
                if let current {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                    Button(current.hasActivatableFaces ? "Activate" : "Deactivate") { toggleActivation(current) }
                        .disabled(!current.hasActivatableFaces && !current.hasDeactivatableFaces)
                        .help("Turn this family on or off (A)")
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                Button("Exit") { close() }
                    .help("Leave the slideshow (Esc)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            Text("← → or Space to move · P to play · A to activate · Esc to exit")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 20)
        .opacity(controlsVisible || hoveringControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: controlsVisible || hoveringControls)
        .onHover { hoveringControls = $0 }
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Behaviour

    private func move(_ step: Int, in count: Int, wrapping: Bool = false) {
        guard count > 0 else { return }
        let next = index + step
        if wrapping {
            index = (next + count) % count
        } else {
            index = min(max(next, 0), count - 1)
        }
    }

    /// Reuses the store's activation flow but shows its prompts in this window, which is the one on screen.
    private func toggleActivation(_ family: FontFamily) {
        if family.hasActivatableFaces {
            library.requestActivate([family])
            if let request = library.pendingActivation {
                library.pendingActivation = nil
                activation = request
            }
        } else if family.hasDeactivatableFaces {
            library.requestDeactivate([family])
            if let request = library.pendingDeactivation {
                library.pendingDeactivation = nil
                deactivation = request
            }
        }
    }

    /// Shows the controls and hides them again after a pause.
    private func wake() {
        if !controlsVisible { controlsVisible = true }
        idle.task?.cancel()
        idle.task = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }

    private func close() {
        isPlaying = false
        dismissWindow(id: PresentationWindow.slideshow)
    }

    private func configure(_ window: NSWindow) {
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = false
        guard !window.styleMask.contains(.fullScreen) else { return }
        DispatchQueue.main.async {
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }
}
