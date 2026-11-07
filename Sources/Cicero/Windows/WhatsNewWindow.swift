import CiceroCore
import Foundation
import Observation
import Sparkle
import SwiftUI

/// One version's notes from CHANGELOG.md, which build-app.sh puts in the app: its `## <version>` heading, the
/// paragraphs under it and its `- ` items, each with its Markdown (bold, code, links) read.
struct ReleaseNotes: Identifiable {
    let version: String
    var paragraphs: [AttributedString] = []
    var items: [AttributedString] = []
    var id: String { version }

    /// Where the links in CHANGELOG.md, which are relative to it, point from the app: the files as they were in the
    /// version's release, as on its GitHub release page. Not main, where a page a beta brings isn't yet.
    private static func base(_ version: String) -> URL? {
        URL(string: "https://github.com/opr-inzn/cicero/blob/v\(version)/")
    }

    /// Every version's notes, newest first, as in the file. Headings that aren't a version, like `## Unreleased`, are
    /// left out with what's under them.
    static func parse(_ text: String) -> [ReleaseNotes] {
        var versions: [ReleaseNotes] = []
        var current: ReleaseNotes?
        // The lines of the paragraph or item being read; `isItem` says which.
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
                // An item that goes on over several lines.
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

    /// The notes in the app, nil for a binary run from .build (swift run), which has none.
    static var bundled: [ReleaseNotes]? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}

/// What's new since the version of Cicero that opened last: after an update, the main window opens the What's New
/// window with the notes of each version since, newest first. Help → What's New in Cicero shows this version's again.
/// At the first launch there's nothing new to show. After a Cicero from before What's New, which kept no version, it
/// shows this version's notes and the version's before it, which that one couldn't show either; but not a beta's
/// before a stable version, as only beta users had that one.
@Observable
final class WhatsNew {
    static let shared = WhatsNew()
    /// The version that showed its notes last, or opened with none to show.
    static let lastVersionKey = "whatsNew.lastVersion"

    /// What the window shows.
    private(set) var notes: [ReleaseNotes] = []
    /// What the main window shows when it appears, as it doesn't at a launch at login or in the menu bar.
    @ObservationIgnored private var pending: [ReleaseNotes] = []

    private static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// At launch, before the library is read, so its saved data still tells a first launch from one after an update.
    func noteLaunch() {
        guard let current = Self.currentVersion, let all = ReleaseNotes.bundled else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: Self.lastVersionKey)
        if let last {
            pending = all.filter { Self.isNewer($0.version, than: last) && !Self.isNewer($0.version, than: current) }
        } else if UserDataStore(locations: .standard).hasSavedData, let index = all.firstIndex(where: { $0.version == current }) {
            pending = [all[index]]
            if all.indices.contains(index + 1), Self.isBeta(current) || !Self.isBeta(all[index + 1].version) {
                pending.append(all[index + 1])
            }
        }
        // Nothing to show waits for no window.
        if pending.isEmpty { defaults.set(current, forKey: Self.lastVersionKey) }
    }

    /// The notes waiting for the main window, which it shows, once.
    func takePending() -> Bool {
        guard !pending.isEmpty else { return false }
        notes = pending
        pending = []
        if let current = Self.currentVersion { UserDefaults.standard.set(current, forKey: Self.lastVersionKey) }
        return true
    }

    /// This version's notes, or the newest before it, for the Help menu. False when the app has none.
    func showLatest() -> Bool {
        guard let current = Self.currentVersion,
              let latest = ReleaseNotes.bundled?.first(where: { !Self.isNewer($0.version, than: current) }) else { return false }
        notes = [latest]
        return true
    }

    /// 0.12.0b1, not 0.12.0.
    private static func isBeta(_ version: String) -> Bool {
        version.contains(where: \.isLetter)
    }

    /// As Sparkle compares them, so a beta like 0.12.0b1 comes before 0.12.0.
    private static func isNewer(_ version: String, than other: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(version, toVersion: other) == .orderedDescending
    }
}

/// The notes of the versions since the last one that opened, under a title, with Done under them. As tall as they are,
/// up to a height where they scroll under Done.
struct WhatsNewWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0

    private static let width: CGFloat = 560
    /// Below the title bar.
    private static let maximumHeight: CGFloat = 600
    /// Between one version's notes and the next: a line of the notes' text, as tall as AppKit sets it.
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
            // Under the title bar, which has room of its own.
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
            // Opaque, so the notes scrolling under it don't show through its label, as they did while the window wasn't
            // in front and the button wasn't blue.
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

/// "Cicero 0.11.0", the paragraphs under it, and its items, each after a dot.
private struct VersionNotes: View {
    let notes: ReleaseNotes

    var body: some View {
        // The first note as far under its version as the notes are from each other.
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
                                // Its middle halfway up a capital letter.
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
