import CiceroCore
import CryptoKit
import Foundation
import Observation
import Sparkle
import SwiftUI

struct ReleaseNotes: Identifiable {
    let version: String
    var paragraphs: [AttributedString] = []
    var items: [AttributedString] = []
    var id: String { version }

    var checksum: String {
        let text = (paragraphs + items).map { String($0.characters) }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func base(_ version: String) -> URL? {
        URL(string: "https://github.com/opr-inzn/cicero/blob/v\(version)/")
    }

    static func parse(_ text: String) -> [ReleaseNotes] {
        var versions: [ReleaseNotes] = []
        var current: ReleaseNotes?
        var lines: [String] = []
        var isItem = false

        func flush() {
            defer { lines = [] }
            guard current != nil, !lines.isEmpty else { return }
            let text = inline(lines.joined(separator: " "), base: base(current?.version ?? ""))
            if isItem { current!.items.append(text) } else { current!.paragraphs.append(text) }
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flush()
                if let current { versions.append(current) }
                let heading = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                current = heading.first?.isNumber == true ? ReleaseNotes(version: heading) : nil
            } else if trimmed.isEmpty {
                flush()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                isItem = true
                lines = [String(trimmed.dropFirst(2))]
            } else if line.first?.isWhitespace == true, isItem, !lines.isEmpty {
                lines.append(trimmed)
            } else {
                if isItem { flush() }
                isItem = false
                lines.append(trimmed)
            }
        }
        flush()
        if let current { versions.append(current) }
        return versions
    }

    private static func inline(_ markdown: String, base: URL?) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var text = try? AttributedString(markdown: markdown, options: options, baseURL: base) else {
            return AttributedString(markdown)
        }
        // A link relative to the file keeps its base apart, which opening it would lose.
        for run in text.runs {
            if let link = run.link { text[run.range].link = link.absoluteURL }
        }
        return text
    }

    static var bundled: [ReleaseNotes]? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}

@Observable
final class WhatsNew {
    static let shared = WhatsNew()
    static let lastVersionKey = "whatsNew.lastVersion"
    static let lastNotesKey = "whatsNew.lastNotes"

    private(set) var notes: [ReleaseNotes] = []
    @ObservationIgnored private var pending: [ReleaseNotes] = []

    private static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func noteLaunch() {
        guard let current = Self.currentVersion, let all = ReleaseNotes.bundled else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: Self.lastVersionKey)
        if let last {
            pending = all.filter { Self.isNewer($0.version, than: last) && !Self.isNewer($0.version, than: current) }
            if pending.isEmpty, last == current, let notes = all.first(where: { $0.version == current }),
               defaults.string(forKey: Self.lastNotesKey) != notes.checksum {
                pending = [notes]
            }
        } else if UserDataStore(locations: .standard).hasSavedData, let notes = all.first(where: { $0.version == current }) {
            pending = [notes]
        }
        if pending.isEmpty { Self.remember(current, notes: all) }
    }

    private static func remember(_ current: String, notes all: [ReleaseNotes]?) {
        UserDefaults.standard.set(current, forKey: lastVersionKey)
        UserDefaults.standard.set(all?.first(where: { $0.version == current })?.checksum, forKey: lastNotesKey)
    }

    func takePending() -> Bool {
        guard !pending.isEmpty else { return false }
        notes = pending
        pending = []
        if let current = Self.currentVersion { Self.remember(current, notes: ReleaseNotes.bundled) }
        return true
    }

    func showLatest() -> Bool {
        guard let current = Self.currentVersion,
              let latest = ReleaseNotes.bundled?.first(where: { !Self.isNewer($0.version, than: current) }) else { return false }
        notes = [latest]
        return true
    }

    private static func isNewer(_ version: String, than other: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(version, toVersion: other) == .orderedDescending
    }
}

struct WhatsNewWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0

    private static let width: CGFloat = 560
    private static let maximumHeight: CGFloat = 600
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .title3)).rounded()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("What’s New in Cicero")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Self.lineHeight) {
                    ForEach(WhatsNew.shared.notes) { VersionNotes(notes: $0) }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .bottomBar {
            Button { dismissWindow() } label: {
                Text("Done").frame(minWidth: 140)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            // Opaque, so the notes scrolling under it don't show through its label while the window isn't in front and the button isn't blue.
            .buttonBorderShape(.capsule)
            .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
        }
        .onExitCommand { dismissWindow() }
        .windowMinimizeBehavior(.disabled)
        .frame(width: Self.width, height: min(contentHeight + barHeight, Self.maximumHeight))
    }
}

private struct VersionNotes: View {
    let notes: ReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cicero \(notes.version)")
                .font(.title2.bold())
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(notes.paragraphs.indices, id: \.self) { Text(notes.paragraphs[$0]) }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes.items.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(.tint)
                                .frame(width: 7, height: 7)
                                .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 5 }
                            Text(notes.items[index])
                        }
                    }
                }
            }
        }
        .font(.title3)
        .lineSpacing(2)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}
