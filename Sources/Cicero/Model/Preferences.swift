import AppKit
import Observation
import CiceroCore
import SwiftUI

/// How previews look everywhere: sample text, size, weight, letter and line spacing, and alignment. Saved in
/// user defaults.
@Observable
final class PreviewSettings {
    static let presets = ["Sphinx of black quartz, judge my vow.", "Hamburgefonstiv", "0123456789 €$£¥ %&@"]
    /// What grid tiles show when no sample text is set: capitals, lowercase, a descender and figures.
    static let tileSample = "Aa Gg 123"

    /// Empty means each family's own name.
    var sampleText: String { didSet { defaults.set(sampleText, forKey: Keys.sampleText) } }
    var size: Double { didSet { defaults.set(size, forKey: Keys.size) } }
    var weight: Double { didSet { defaults.set(weight, forKey: Keys.weight) } }
    /// Letter spacing in percent of the em.
    var tracking: Double { didSet { defaults.set(tracking, forKey: Keys.tracking) } }
    /// Line height in percent of the size, wherever a sample runs over several lines; 120 is what layout apps
    /// call automatic leading.
    var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) } }
    /// How samples line up in specimens and Quick Look. Font pages have their own.
    var alignment: SampleAlignment { didSet { defaults.set(alignment.rawValue, forKey: Keys.alignment) } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let sampleText = "preview.sampleText"
        static let size = "preview.size"
        static let weight = "preview.weight"
        static let tracking = "preview.tracking"
        static let lineSpacing = "preview.lineSpacing"
        static let alignment = "preview.alignment"
    }

    init() {
        sampleText = defaults.string(forKey: Keys.sampleText) ?? ""
        size = defaults.object(forKey: Keys.size) as? Double ?? 32
        weight = defaults.object(forKey: Keys.weight) as? Double ?? 400
        tracking = defaults.object(forKey: Keys.tracking) as? Double ?? 0
        lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 120
        alignment = defaults.string(forKey: Keys.alignment).flatMap(SampleAlignment.init) ?? .leading
    }

    func text(for family: Family) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }

    /// Points of extra space between letters at a size.
    func kerning(at size: Double) -> Double {
        size * tracking / 100
    }

    /// The distance from one line's baseline to the next at a size, in points.
    func lineHeight(at size: Double) -> Double {
        size * lineSpacing / 100
    }
}

/// Left, centred or right, for samples.
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

    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var paragraph: NSTextAlignment {
        switch self {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
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
