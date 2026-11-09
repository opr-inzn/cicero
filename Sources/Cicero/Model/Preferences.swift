import AppKit
import Observation
import CiceroCore
import SwiftUI

@Observable
final class PreviewSettings {
    static let presets = ["Sphinx of black quartz, judge my vow.", "Lorem ipsum dolor sit amet", "Hamburgefonstiv", "0123456789 €$£¥ %&@"]
    static let tileSample = "Aa Gg 123"
    static let sizes: ClosedRange<Double> = 24...200
    static let lineSpacings: ClosedRange<Double> = 80...200

    var sampleText: String { didSet { SavedSoon.set(sampleText, forKey: Keys.sampleText) } }
    var savedPresets: [String] { didSet { defaults.set(savedPresets, forKey: Keys.savedPresets) } }
    var size: Double { didSet { SavedSoon.set(size, forKey: Keys.size) } }
    let weight = 400.0
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

    func isSavedPreset(_ text: String) -> Bool { savedPresets.contains(text) }

    func canSavePreset(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.presets.contains(text) && !isSavedPreset(text)
    }

    func text(for family: Family) -> String {
        sampleText.isEmpty ? family.name : sampleText
    }
}

enum SavedSoon {
    // Only in memory until saved: read a value from where it's kept (`PreviewSettings`, `SavedSoon.Value`), never from the defaults.
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
        // SwiftUI draws every view with an `@AppStorage` again whenever anything is saved to the defaults, whatever the key.
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

    @Observable
    final class Value<Stored> {
        @ObservationIgnored let key: String
        var value: Stored { didSet { SavedSoon.set(value, forKey: key) } }

        init(_ key: String, default value: Stored) {
            self.key = key
            self.value = UserDefaults.standard.object(forKey: key) as? Stored ?? value
        }
    }

    static let compareText = Value("compare.text", default: "")
    static let toolboxText = Value("toolbox.text", default: "")
}

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
        // On NSApp, so every window, sheet and popover follows.
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
    static let whatsNew = "whatsNew"
}
