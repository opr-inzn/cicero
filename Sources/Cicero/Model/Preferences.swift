import AppKit
import Observation
import CiceroCore
import SwiftUI

/// How previews look everywhere: sample text, size and line spacing, and the weight they're in. Saved in user defaults. Tracking and
/// alignment are the font page's own (see `TypeTester`): the overview sets every font with its own spacing, lined up
/// on the left.
@Observable
final class PreviewSettings {
    static let presets = ["Sphinx of black quartz, judge my vow.", "Lorem ipsum dolor sit amet", "Hamburgefonstiv", "0123456789 €$£¥ %&@"]
    /// What grid tiles show when no sample text is set: capitals, lowercase, a descender and figures.
    static let tileSample = "Aa Gg 123"
    /// Preview Options' Size; a smaller size saved before 24 pt was the least goes up to it.
    static let sizes: ClosedRange<Double> = 24...200
    /// The font page's Leading, in percent of the size; a larger leading saved before 200 % was the most comes down to it.
    static let lineSpacings: ClosedRange<Double> = 80...200

    /// Empty means each family's own name. Saved a moment after typing stops (`SavedSoon`), as the size and line
    /// spacing are after a slider stops.
    var sampleText: String { didSet { SavedSoon.set(sampleText, forKey: Keys.sampleText) } }
    /// Preview texts saved with Save as Preset, in the order saved: Presets lists them before `presets`.
    var savedPresets: [String] { didSet { defaults.set(savedPresets, forKey: Keys.savedPresets) } }
    var size: Double { didSet { SavedSoon.set(size, forKey: Keys.size) } }
    /// What previews show a family in, where a search names no style: its regular style, the one nearest 400. Preview
    /// Options had a Weight slider up to 0.10.2; what it saved is forgotten.
    let weight = 400.0
    /// The font page's line height, in percent of the size; 120 is what layout apps call automatic leading. Every
    /// font page shares it. Preview Options had it up to 0.11.0, and Quick Look used it.
    var lineSpacing: Double { didSet { SavedSoon.set(lineSpacing, forKey: Keys.lineSpacing) } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let sampleText = "preview.sampleText"
        static let savedPresets = "preview.savedPresets"
        static let size = "preview.size"
        static let weight = "preview.weight"
        static let lineSpacing = "preview.lineSpacing"
    }

    init() {
        sampleText = defaults.string(forKey: Keys.sampleText) ?? ""
        savedPresets = defaults.stringArray(forKey: Keys.savedPresets) ?? []
        size = min(max(defaults.object(forKey: Keys.size) as? Double ?? 32, Self.sizes.lowerBound), Self.sizes.upperBound)
        defaults.removeObject(forKey: Keys.weight)
        lineSpacing = min(max(defaults.object(forKey: Keys.lineSpacing) as? Double ?? 120, Self.lineSpacings.lowerBound),
                          Self.lineSpacings.upperBound)
    }

    /// Whether a text, the preview text or Compare's, is one of the presets saved with Save as Preset.
    func isSavedPreset(_ text: String) -> Bool { savedPresets.contains(text) }

    /// Whether Save as Preset can save a text: it has something to see, and isn't a preset already.
    func canSavePreset(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.presets.contains(text) && !isSavedPreset(text)
    }

    func text(for family: Family) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }
}

/// Saves to the user defaults a second after the last change and as Cicero quits, rather than with each change. SwiftUI
/// draws every view with an `@AppStorage` again whenever anything is saved to the defaults, whatever the key, so each
/// letter typed in Preview Options, Compare or the Character Toolbox, and each step of a size slider, drew the browser
/// again, and Settings and Compare where they were open. What's waiting is only in memory: read it from where it's
/// kept (`PreviewSettings`, `SavedSoon.Value`), never from the defaults. The font page's tester does the same
/// (`TesterTextStore`).
enum SavedSoon {
    private static var pending: [String: Any] = [:]
    private static var save: Task<Void, Never>?
    private static var observesQuit = false

    static func set(_ value: Any, forKey key: String) {
        pending[key] = value
        if !observesQuit {
            observesQuit = true
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { flush() }
            }
        }
        save?.cancel()
        save = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    static func flush() {
        save?.cancel()
        save = nil
        let values = pending
        pending = [:]
        for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
    }

    /// A value kept in the defaults and saved soon, for a view that would otherwise have it as an `@AppStorage`.
    @Observable
    final class Value<Stored> {
        @ObservationIgnored let key: String
        var value: Stored { didSet { SavedSoon.set(value, forKey: key) } }

        init(_ key: String, default value: Stored) {
            self.key = key
            self.value = UserDefaults.standard.object(forKey: key) as? Stored ?? value
        }
    }

    /// Compare's text and the Character Toolbox's.
    static let compareText = Value("compare.text", default: "")
    static let toolboxText = Value("toolbox.text", default: "")
}

/// Left, centred or right, for a font page's text.
enum SampleAlignment: String, CaseIterable {
    case leading, center, trailing

    var title: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        }
    }

    var icon: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    var paragraph: NSTextAlignment {
        switch self {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }
}

/// Light or dark for the whole app, or whatever macOS uses. Set on NSApp so every window, sheet
/// and popover follows.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func applySaved() {
        (UserDefaults.standard.string(forKey: defaultsKey).flatMap(Appearance.init) ?? .system).apply()
    }
}

enum BrowserMode: String, CaseIterable {
    case list, grid, specimens

    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        case .specimens: "Specimens"
        }
    }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .specimens: "rectangle.grid.1x2"
        }
    }
}

enum WindowID {
    static let main = "main"
    static let toolbox = "toolbox"
    static let compare = "compare"
}
