import AppKit
import Observation
import CiceroCore
import SwiftUI

/// How previews look everywhere: sample text, size and line spacing, and the weight they're in. Saved in user defaults. Tracking and
/// alignment are the font page's own (see `TypeTester`): the overview sets every font with its own spacing, lined up
/// on the left.
@Observable
final class PreviewSettings {
    static let presets = ["Sphinx of black quartz, judge my vow.", "Hamburgefonstiv", "0123456789 €$£¥ %&@"]
    /// What grid tiles show when no sample text is set: capitals, lowercase, a descender and figures.
    static let tileSample = "Aa Gg 123"
    /// Preview Options' Size; a smaller size saved before 24 pt was the least goes up to it.
    static let sizes: ClosedRange<Double> = 24...200

    /// Empty means each family's own name.
    var sampleText: String { didSet { defaults.set(sampleText, forKey: Keys.sampleText) } }
    /// Preview texts saved with Save as Preset, in the order saved: Presets lists them before `presets`.
    var savedPresets: [String] { didSet { defaults.set(savedPresets, forKey: Keys.savedPresets) } }
    var size: Double { didSet { defaults.set(size, forKey: Keys.size) } }
    /// What previews show a family in, where a search names no style: its regular style, the one nearest 400. Preview
    /// Options had a Weight slider up to 0.10.2; what it saved is forgotten.
    let weight = 400.0
    /// Line height in percent of the size, wherever a sample runs over several lines; 120 is what layout apps
    /// call automatic leading.
    var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) } }

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
        lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 120
    }

    /// Whether the preview text is one of the presets saved with Save as Preset.
    var isSavedPreset: Bool { savedPresets.contains(sampleText) }

    /// Whether Save as Preset can save the preview text: it has something to see, and isn't a preset already.
    var canSavePreset: Bool {
        !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.presets.contains(sampleText) && !isSavedPreset
    }

    func text(for family: Family) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }

    /// The distance from one line's baseline to the next at a size, in points.
    func lineHeight(at size: Double) -> Double {
        size * lineSpacing / 100
    }
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
