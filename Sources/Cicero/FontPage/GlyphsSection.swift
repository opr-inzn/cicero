import CiceroCore
import SwiftUI

/// Every character a style has, grouped by Unicode block, then the ligatures it makes, by feature, under headers like
/// the blocks'; with a filter by character, Unicode name or U+ code that takes in the ligatures too. Several views in a
/// row, so each block's header pins in the page's lazy stack and its cells are rows of it.
struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    /// Cells per row, from the page's width.
    let columns: Int
    /// The style's characters.
    let sections: [GlyphSection]
    let ligatures: [LigatureGroup]
    @State private var query = ""
    @State private var popover: UInt32?

    nonisolated static let cell: CGFloat = 52
    nonisolated static let spacing: CGFloat = 4
    nonisolated static let inset: CGFloat = 24
    /// The size a cell's character, or ligature, is set at.
    static let glyphSize: CGFloat = 26

    /// How many cells fit across a page this wide.
    nonisolated static func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + spacing) / (cell + spacing)))
    }

    var body: some View {
        let face = family.face(nearestWeight: preview.weight).face
        let shown = filtered(sections)
        let shownLigatures = filtered(ligatures)
        HStack(spacing: 12) {
            Text("Glyphs").font(.title2.weight(.semibold))
            Text(count)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            TextField("Filter", text: $query, prompt: Text("Character, name or U+ code"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
        }
        .padding(.horizontal, Self.inset)
        // Well clear of the styles above, and close to the blocks it heads.
        .padding(.top, 56)
        .padding(.bottom, 4)
        if shown.isEmpty && shownLigatures.isEmpty {
            ContentUnavailableView(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                                   description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else {
            ForEach(shown) { section in
                Section {
                    // Rows of the page's stack, not a LazyVGrid per block in it. The stack guesses the height of blocks
                    // it hasn't placed from those it has, and blocks run from one row to hundreds, so every correction
                    // shifted the page and changed which blocks were placed: it re-laid itself out at full CPU. Rows
                    // of fixed cells are all one height, so the guesses are right.
                    let rows = (section.scalars.count + columns - 1) / columns
                    ForEach(0..<rows, id: \.self) { row in
                        glyphRow(section.scalars[row * columns ..< min((row + 1) * columns, section.scalars.count)], face: face)
                            .padding(.horizontal, Self.inset)
                            .padding(.bottom, row == rows - 1 ? 18 : Self.spacing)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(section.title).font(.headline)
                        Text("— \(section.scalars.count.formatted())").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 4)
                    .background(Color.canvas)
                }
            }
            // Glyphs with no character of their own, after those with one.
            if !shownLigatures.isEmpty {
                LigaturesSection(face: face, columns: columns, groups: shownLigatures)
            }
            Color.clear.frame(height: 6)
        }
    }

    /// "124 characters", and the ligatures when there are any: "124 characters · 3 ligatures".
    private var count: String {
        let characters = sections.reduce(0) { $0 + $1.scalars.count }
        let ligatureCount = ligatures.reduce(0) { $0 + $1.ligatures.count }
        let text = characters == 1 ? "1 character" : "\(characters.formatted()) characters"
        guard ligatureCount > 0 else { return text }
        return text + " · " + (ligatureCount == 1 ? "1 ligature" : "\(ligatureCount.formatted()) ligatures")
    }

    /// One popover per row, pointing at the clicked cell, rather than one per cell: each is worked out
    /// again whenever the page updates. The cells share out the row's width, so they reach the page's edge
    /// whatever it is, without the page drawing them again as it changes; a short last row keeps their width.
    private func glyphRow(_ scalars: ArraySlice<UInt32>, face: FontFace) -> some View {
        let column = popover.flatMap { scalars.firstIndex(of: $0) }.map { $0 - scalars.startIndex }
        // The clicked cell's bottom middle, within two points: the cells are as wide as the row allows.
        let anchor = UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1)
        return HStack(spacing: Self.spacing) {
            ForEach(scalars, id: \.self) { scalar in
                glyph(scalar, face: face)
            }
            ForEach(scalars.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: Self.cell)
            }
        }
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .point(anchor)) {
            if let popover {
                VStack(spacing: 10) {
                    character(popover, face: face, size: 96)
                        .frame(minWidth: 160, minHeight: 130)
                    Text(GlyphSection.name(of: popover)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                    Text(String(format: "U+%04X", popover)).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: 260)
            }
        }
    }

    private func glyph(_ scalar: UInt32, face: FontFace) -> some View {
        character(scalar, face: face, size: Self.glyphSize)
            .frame(minWidth: Self.cell, maxWidth: .infinity, minHeight: Self.cell, maxHeight: Self.cell)
            .background(.quaternary.opacity(popover == scalar ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture { popover = scalar }
    }

    /// A character set in the font. A mark that combines with the character before it (an acute, a cedilla) is drawn from
    /// its outline instead: set on its own it has nothing to sit on and showed nothing.
    @ViewBuilder
    private func character(_ scalar: UInt32, face: FontFace, size: CGFloat) -> some View {
        if Self.isCombining(scalar), let glyph = Self.glyph(of: scalar, in: FontLoader.shared.font(face, size: size, weight: preview.weight)) {
            GlyphImage(face: face, glyph: glyph, size: size, weight: preview.weight)
        } else {
            FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: face, size: size, weight: preview.weight,
                     features: model.features(for: family))
        }
    }

    private static func isCombining(_ scalar: UInt32) -> Bool {
        switch Unicode.Scalar(scalar)?.properties.generalCategory {
        case .nonspacingMark, .enclosingMark: true
        default: false
        }
    }

    /// The glyph the font maps a character to, if it has one.
    private static func glyph(of scalar: UInt32, in font: CTFont) -> CGGlyph? {
        guard let character = Unicode.Scalar(scalar) else { return nil }
        var units = Array(String(Character(character)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    private func filtered(_ sections: [GlyphSection]) -> [GlyphSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sections }
        let code = trimmed.uppercased().replacingOccurrences(of: "U+", with: "").replacingOccurrences(of: "0X", with: "")
        let codeValue = UInt32(code, radix: 16)
        let scalars = Set(trimmed.unicodeScalars.map(\.value))
        let lower = trimmed.lowercased()
        return sections.compactMap { section in
            let matches = section.scalars.filter { scalar in
                scalars.contains(scalar) || scalar == codeValue
                    || (trimmed.count > 1 && (GlyphSection.name(of: scalar)?.lowercased().contains(lower) ?? false))
            }
            return matches.isEmpty ? nil : GlyphSection(title: section.title, scalars: matches)
        }
    }

    /// The ligatures whose characters hold what's typed ("f" finds ff, fi and ffl), or one with that U+ code.
    private func filtered(_ groups: [LigatureGroup]) -> [LigatureGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return groups }
        let code = UInt32(trimmed.uppercased().replacingOccurrences(of: "U+", with: "").replacingOccurrences(of: "0X", with: ""), radix: 16)
        return groups.compactMap { group in
            let matches = group.ligatures.filter { ligature in
                ligature.text.localizedCaseInsensitiveContains(trimmed) || code.map(ligature.characters.contains) ?? false
            }
            return matches.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: matches)
        }
    }
}
