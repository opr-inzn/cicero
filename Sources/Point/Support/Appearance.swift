import AppKit

/// Light or dark for the whole app, or whatever macOS uses. Set on NSApp so every window, sheet and
/// popover follows, not just the views that read a SwiftUI color scheme.
enum AppAppearance: String, CaseIterable, Identifiable {
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

    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func applySaved() {
        (UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppAppearance.init) ?? .system).apply()
    }
}
