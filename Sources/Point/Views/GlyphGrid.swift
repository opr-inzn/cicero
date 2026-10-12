import AppKit
import SwiftUI

/// Every character the font covers, grouped by script, with a filter and a popover per glyph.
struct GlyphGrid: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    let family: FontFamily

    @State private var sections: [CharacterSection] = []
    @State private var shown: [CharacterSection] = []
    @State private var query = ""
    @State private var selected: UInt32?
    @State private var isLoading = true
    /// Bumped when a face finishes loading, so the filter runs again over the new sections.
    @State private var generation = 0

    private struct FilterKey: Equatable {
        var generation: Int
        var query: String
    }

    var body: some View {
        let face = family.face(nearestWeight: Int(preview.weight))
        let features = library.features(for: family)
        VStack(spacing: 0) {
            filterBar
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 2)], spacing: 2, pinnedViews: .sectionHeaders) {
                    ForEach(shown) { section in
                        Section {
                            ForEach(section.scalars, id: \.self) { value in
                                cell(value, face: face.face, features: features)
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .overlay { placeholder }
        }
        .task(id: face.id) { await load(face.face) }
        .task(id: FilterKey(generation: generation, query: query)) { await filter() }
    }

    // MARK: Filter

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("Filter", text: $query, prompt: Text("Character, name or U+ code"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            Spacer()
            Text(countLabel)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var countLabel: String {
        let total = sections.reduce(0) { $0 + $1.scalars.count }
        guard !query.isEmpty else { return total == 1 ? "1 character" : "\(total.formatted()) characters" }
        let visible = shown.reduce(0) { $0 + $1.scalars.count }
        return "\(visible.formatted()) of \(total.formatted())"
    }

    @ViewBuilder
    private var placeholder: some View {
        if isLoading && sections.isEmpty {
            ProgressView()
        } else if !isLoading && sections.isEmpty {
            ContentUnavailableView("No Characters", systemImage: "character",
                                   description: Text("Point couldn't read a character set from this font."))
        } else if shown.isEmpty && !query.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func load(_ face: FontFace) async {
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { CharacterSections.compute(for: face) }.value
        guard !Task.isCancelled else { return }
        sections = result
        isLoading = false
        generation += 1
    }

    private func filter() async {
        let source = sections
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            shown = source
            return
        }
        let matcher = GlyphQuery(text)
        let result = await Task.detached(priority: .userInitiated) {
            source.compactMap { section -> CharacterSection? in
                let hits = section.scalars.filter(matcher.matches)
                return hits.isEmpty ? nil : CharacterSection(title: section.title, scalars: hits)
            }
        }.value
        guard !Task.isCancelled else { return }
        shown = result
    }

    // MARK: Grid

    private func sectionHeader(_ section: CharacterSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Self.sentenceCase(section.title))
                .font(.headline)
            Text("— \(section.scalars.count.formatted())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    private func cell(_ value: UInt32, face: FontFace, features: [FeatureSetting]) -> some View {
        let character = Unicode.Scalar(value).map { String(Character($0)) } ?? ""
        return Text(character)
            .font(Font(FontCache.shared.font(face, size: 26, weight: preview.weight, features: features)))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected == value ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5) }
            .contentShape(.rect)
            .onTapGesture { selected = value }
            .popover(isPresented: Binding(
                get: { selected == value },
                set: { if !$0 { selected = nil } }
            )) {
                CharacterPopover(value: value, face: face, weight: preview.weight)
            }
    }

    /// "CJK Ideographs" → "CJK ideographs": only the first word and acronyms keep their capitals.
    private static func sentenceCase(_ title: String) -> String {
        title.split(separator: " ").enumerated().map { index, word in
            index == 0 || word.allSatisfy(\.isUppercase) ? String(word) : word.lowercased()
        }.joined(separator: " ")
    }
}

/// Matches a character against what was typed: the character itself (either case), a code point
/// such as "U+00E9" or "00E9", or part of its Unicode name such as "acute" or "arrow".
struct GlyphQuery: Sendable {
    private let exact: Set<UInt32>
    private let hexPrefix: String?
    private let hexValue: UInt32?
    private let namePart: String?

    init(_ text: String) {
        var exact = Set<UInt32>()
        let composed = text.precomposedStringWithCanonicalMapping
        if composed.unicodeScalars.count == 1 {
            for variant in [composed, composed.uppercased(), composed.lowercased()] where variant.unicodeScalars.count == 1 {
                exact.insert(variant.unicodeScalars.first!.value)
            }
        }
        self.exact = exact

        // "U+" takes any number of digits; bare hex needs four or more so short words still search names.
        let upper = text.uppercased()
        let prefixed = upper.hasPrefix("U+")
        let digits = prefixed ? String(upper.dropFirst(2)) : upper
        if !digits.isEmpty, digits.allSatisfy(\.isHexDigit), prefixed || digits.count >= 4 {
            hexPrefix = digits
            hexValue = prefixed ? UInt32(digits, radix: 16) : nil
        } else {
            hexPrefix = nil
            hexValue = nil
        }
        namePart = text.count >= 2 && !prefixed ? upper : nil
    }

    func matches(_ value: UInt32) -> Bool {
        if exact.contains(value) { return true }
        if let hexValue, hexValue == value { return true }
        if let hexPrefix, String(format: "%04X", value).hasPrefix(hexPrefix) { return true }
        if let namePart, let scalar = Unicode.Scalar(value) {
            if let name = scalar.properties.name, name.contains(namePart) { return true }
            if let alias = scalar.properties.nameAlias, alias.contains(namePart) { return true }
        }
        return false
    }
}

struct CharacterPopover: View {
    let value: UInt32
    let face: FontFace
    let weight: Double

    var body: some View {
        let scalar = Unicode.Scalar(value)
        let character = scalar.map { String(Character($0)) } ?? ""
        VStack(spacing: 10) {
            Text(character)
                .font(Font(FontCache.shared.font(face, size: 120, weight: weight)))
                .frame(minWidth: 180, minHeight: 160)
            Text(scalar?.properties.name?.capitalized ?? scalar?.properties.nameAlias?.capitalized ?? "Unnamed")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
            Text(String(format: "U+%04X", value))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Copy Character") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(character, forType: .string)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 240)
    }
}
