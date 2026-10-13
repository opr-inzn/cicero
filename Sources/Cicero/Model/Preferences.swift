import AppKit
import Observation
import CiceroCore

/// How previews look everywhere: sample text, size, weight and letter spacing. Saved in user defaults.
@Observable
final class PreviewSettings {
    static let presets = ["Sphinx of black quartz, judge my vow.", "Hamburgefonstiv", "0123456789 €$£¥ %&@", "ÀÉÎÕÜ ñçß øæœ"]
    /// What grid tiles show when no sample text is set: capitals, lowercase, a descender and figures.
    static let tileSample = "Aa Gg 123"

    /// Empty means each family's own name.
    var sampleText: String { didSet { defaults.set(sampleText, forKey: Keys.sampleText) } }
    var size: Double { didSet { defaults.set(size, forKey: Keys.size) } }
    var weight: Double { didSet { defaults.set(weight, forKey: Keys.weight) } }
    /// Letter spacing in percent of the em.
    var tracking: Double { didSet { defaults.set(tracking, forKey: Keys.tracking) } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let sampleText = "preview.sampleText"
        static let size = "preview.size"
        static let weight = "preview.weight"
        static let tracking = "preview.tracking"
    }

    init() {
        sampleText = defaults.string(forKey: Keys.sampleText) ?? ""
        size = defaults.object(forKey: Keys.size) as? Double ?? 32
        weight = defaults.object(forKey: Keys.weight) as? Double ?? 400
        tracking = defaults.object(forKey: Keys.tracking) as? Double ?? 0
    }

    func text(for family: Family) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }

    /// Points of extra space between letters at a size.
    func kerning(at size: Double) -> Double {
        size * tracking / 100
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

extension TemporaryScope {
    var menuTitle: String {
        switch self {
        case .untilQuit: "Until Cicero Quits"
        case .untilLogout: "Until You Log Out"
        case .whileAppsRun: "While Its App Is Open"
        }
    }
}

enum WindowID {
    static let main = "main"
    static let toolbox = "toolbox"
    static let compare = "compare"
}
