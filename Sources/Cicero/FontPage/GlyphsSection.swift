import AppKit
import CiceroCore
import SwiftUI

/// Every character a style has, and the glyphs its features draw in place of characters', like tabular figures, by
/// group (see `GlyphGroup`), the ligatures it makes, by feature, in the Ligatures group's place, under headers like the
/// groups'; with a filter by character, Unicode name or U+ code that takes in the ligatures and feature glyphs too.
/// The glyphs the features chosen in the Info panel draw follow the characters they're for, marked with a dot.
/// Several views in a row, so each group's cells are rows of the page's lazy stack.
struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    /// Cells per row, from the page's width.
    let columns: Int
    /// The style's characters, but those listed as ligatures, and its feature glyphs.
    let sections: [GlyphSection]
    /// All of them.
    let characterCount: Int
    let ligatures: [LigatureGroup]
    /// The character a ligature's glyph is too, like U+FB01 for ﬁ.
    let ligatureCharacters: [CGGlyph: UInt32]
    @State private var query = ""
    @State private var popover: Cell?
    /// What the chosen features draw in place of characters' glyphs.
    @State private var alternates: [UInt32: FeatureAlternate] = [:]

    /// A cell of the grid: a character, a glyph a feature draws for one, or one a chosen feature draws for it.
    private enum Cell: Hashable {
        case character(UInt32)
        case feature(FeatureGlyph)
        case alternate(UInt32, CGGlyph)
    }

    private struct AlternatesRequest: Hashable {
        let face: FaceID
        let features: [FeatureSetting]
    }

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
        .task(id: AlternatesRequest(face: face.id, features: model.features(for: family))) {
            let features = model.features(for: family), scalars = sections.flatMap(\.scalars)
            alternates = features.isEmpty ? [:] : await Task.detached(priority: .userInitiated) {
                FeatureAlternates.read(face, scalars: scalars, features: features)
            }.value
        }
        .padding(.horizontal, Self.inset)
        // Well clear of the styles above, and close to the groups it heads.
        .padding(.top, 56)
        .padding(.bottom, 4)
        if shown.isEmpty && shownLigatures.isEmpty {
            ContentUnavailableView(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                                   description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else {
            ForEach(shown.filter { $0.group <= .ligatures }) { section in
                self.section(section, face: face)
            }
            // In the Ligatures group's place, after its characters, like ﬀ, that no feature makes.
            if !shownLigatures.isEmpty {
                LigaturesSection(face: face, variations: model.variations(for: family), columns: columns, groups: shownLigatures,
                                 characters: ligatureCharacters)
            }
            ForEach(shown.filter { $0.group > .ligatures }) { section in
                self.section(section, face: face)
            }
            Color.clear.frame(height: 6)
        }
    }

    private func section(_ section: GlyphSection, face: FontFace) -> some View {
        let cells = section.scalars.flatMap { scalar in
            [Cell.character(scalar)] + (alternates[scalar].map { [Cell.alternate(scalar, $0.glyph)] } ?? [])
        } + section.glyphs.map(Cell.feature)
        return Section {
            // Rows of the page's stack, not a LazyVGrid per group in it. The stack guesses the height of groups it
            // hasn't placed from those it has, and groups run from one row to hundreds, so every correction shifted
            // the page and changed which groups were placed: it re-laid itself out at full CPU. Rows of fixed cells
            // are all one height, so the guesses are right.
            let rows = (cells.count + columns - 1) / columns
            ForEach(0..<rows, id: \.self) { row in
                glyphRow(cells[row * columns ..< min((row + 1) * columns, cells.count)], face: face)
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, row == rows - 1 ? 18 : Self.spacing)
            }
        } header: {
            HStack(spacing: 6) {
                Text(section.title).font(.headline)
                // The font's own, not what the chosen features add.
                Text("— \((section.scalars.count + section.glyphs.count).formatted())").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 4)
        }
    }

    /// "124 characters", and the ligatures when there are any: "124 characters · 3 ligatures".
    private var count: String {
        let characters = characterCount
        let ligatureCount = ligatures.reduce(0) { $0 + $1.ligatures.count }
        let text = characters == 1 ? "1 character" : "\(characters.formatted()) characters"
        guard ligatureCount > 0 else { return text }
        return text + " · " + (ligatureCount == 1 ? "1 ligature" : "\(ligatureCount.formatted()) ligatures")
    }

    /// One popover per row, pointing at the clicked cell, rather than one per cell: each is worked out
    /// again whenever the page updates. The cells share out the row's width, so they reach the page's edge
    /// whatever it is, without the page drawing them again as it changes; a short last row keeps their width.
    private func glyphRow(_ cells: ArraySlice<Cell>, face: FontFace) -> some View {
        let column = popover.flatMap { cells.firstIndex(of: $0) }.map { $0 - cells.startIndex }
        // The clicked cell's bottom middle, within two points: the cells are as wide as the row allows.
        let anchor = UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1)
        return HStack(spacing: Self.spacing) {
            ForEach(cells, id: \.self) { cell in
                glyph(cell, face: face)
            }
            ForEach(cells.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: Self.cell)
            }
        }
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .point(anchor)) {
            if let popover {
                details(popover, face: face)
            }
        }
    }

    /// A character's name, codes and keystroke, and a button that copies it; for a feature's glyph, the character's,
    /// and the feature's name.
    private func details(_ cell: Cell, face: FontFace) -> some View {
        VStack(spacing: 10) {
            switch cell {
            case .character(let scalar):
                character(scalar, face: face, size: 96)
                    .frame(minWidth: 160, minHeight: 130)
                Text(GlyphSection.name(of: scalar)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: scalar)
                Button("Copy Character", systemImage: "doc.on.doc") { Self.copy(Self.text(scalar)) }
                    .help("Copies “\(Self.text(scalar))”")
            case .feature(let glyph):
                GlyphImage(face: face, glyph: glyph.glyph, size: 96, weight: preview.weight, variations: model.variations(for: family))
                    .frame(width: 160, height: 130)
                Text(GlyphSection.name(of: glyph.character)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                Text("\(glyph.featureName) (\(glyph.feature))").font(.callout).foregroundStyle(.secondary)
                CharacterCodesGrid(scalar: glyph.character)
                // The glyph has no code of its own: what's copied is the character, which the font draws like this
                // where the feature is on.
                Button("Copy Character", systemImage: "doc.on.doc") { Self.copy(Self.text(glyph.character)) }
                    .help("Copies “\(Self.text(glyph.character))”, which this font draws like this with \(glyph.featureName) on")
            case .alternate(let scalar, let glyph):
                let names = alternates[scalar]?.featureNames.formatted(.list(type: .and)) ?? ""
                GlyphImage(face: face, glyph: glyph, size: 96, weight: preview.weight, variations: model.variations(for: family))
                    .frame(width: 160, height: 130)
                Text(GlyphSection.name(of: scalar)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                Text(names).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: scalar)
                Button("Copy Character", systemImage: "doc.on.doc") { Self.copy(Self.text(scalar)) }
                    .help("Copies “\(Self.text(scalar))”, which this font draws like this with \(names) on")
            }
        }
        .padding(16)
        .frame(maxWidth: 260)
    }

    /// Copy Character, Copy Unicode and Copy HTML Entity, for a cell's right-click menu: a feature's glyph copies the
    /// character it's drawn for.
    @ViewBuilder
    private func copyMenu(_ cell: Cell) -> some View {
        let scalar = switch cell {
        case .character(let scalar), .alternate(let scalar, _): scalar
        case .feature(let glyph): glyph.character
        }
        Button("Copy Character", systemImage: "doc.on.clipboard") { Self.copy(Self.text(scalar)) }
        Button("Copy Unicode", systemImage: "doc.on.clipboard") { Self.copy(CharacterCodes.unicode(scalar)) }
        Button("Copy HTML Entity", systemImage: "doc.on.clipboard") { Self.copy(CharacterCodes.htmlEntity(scalar)) }
    }

    /// Puts text on the clipboard, as plain text.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A character as text; nothing for a code that isn't one.
    static func text(_ scalar: UInt32) -> String {
        Unicode.Scalar(scalar).map { String(Character($0)) } ?? ""
    }

    private func glyph(_ cell: Cell, face: FontFace) -> some View {
        Group {
            switch cell {
            case .character(let scalar): character(scalar, face: face, size: Self.glyphSize)
            case .feature(let glyph):
                GlyphImage(face: face, glyph: glyph.glyph, size: Self.glyphSize, weight: preview.weight, variations: model.variations(for: family))
            case .alternate(_, let glyph):
                GlyphImage(face: face, glyph: glyph, size: Self.glyphSize, weight: preview.weight, variations: model.variations(for: family))
            }
        }
        .frame(minWidth: Self.cell, maxWidth: .infinity, minHeight: Self.cell, maxHeight: Self.cell)
        .background(.quaternary.opacity(popover == cell ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
        // A chosen feature's glyph, after the character's own.
        .overlay(alignment: .topTrailing) {
            if case .alternate = cell {
                Circle().fill(.green).frame(width: 6, height: 6).padding(5)
            }
        }
        .contentShape(.rect)
        .onTapGesture { popover = cell }
        // VoiceOver opens the popover as a click does.
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { popover = cell }
        .contextMenu { copyMenu(cell) }
    }

    /// A character set in the font. A mark that combines with the character before it (an acute, a cedilla) is drawn from
    /// its outline instead: set on its own it has nothing to sit on and showed nothing.
    @ViewBuilder
    private func character(_ scalar: UInt32, face: FontFace, size: CGFloat) -> some View {
        if Self.isCombining(scalar), let glyph = Self.glyph(of: scalar, in: FontLoader.shared.font(face, size: size, weight: preview.weight)) {
            GlyphImage(face: face, glyph: glyph, size: size, weight: preview.weight, variations: model.variations(for: family))
        } else {
            FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: face, size: size, weight: preview.weight,
                     variations: model.variations(for: family))
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
        func matches(_ scalar: UInt32) -> Bool {
            scalars.contains(scalar) || scalar == codeValue
                || (trimmed.count > 1 && (GlyphSection.name(of: scalar)?.lowercased().contains(lower) ?? false))
        }
        return sections.compactMap { section in
            // A feature's glyph by its character, or the feature's name or tag.
            let characters = section.scalars.filter(matches)
            let glyphs = section.glyphs.filter { glyph in
                matches(glyph.character) || (trimmed.count > 1 && (glyph.featureName.lowercased().contains(lower) || glyph.feature == lower))
            }
            return characters.isEmpty && glyphs.isEmpty ? nil : GlyphSection(group: section.group, scalars: characters, glyphs: glyphs)
        }
    }

    /// The ligatures whose characters hold what's typed ("f" finds ff, fi and ffl), with that U+ code, or that are the
    /// character typed.
    private func filtered(_ groups: [LigatureGroup]) -> [LigatureGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return groups }
        let code = UInt32(trimmed.uppercased().replacingOccurrences(of: "U+", with: "").replacingOccurrences(of: "0X", with: ""), radix: 16)
        return groups.compactMap { group in
            let matches = group.ligatures.filter { ligature in
                // Its own character too, like ﬁ or U+FB01.
                let own = ligatureCharacters[ligature.glyph]
                return ligature.text.localizedCaseInsensitiveContains(trimmed)
                    || code.map { ligature.characters.contains($0) || own == $0 } ?? false
                    || own.flatMap(Unicode.Scalar.init).map { String(Character($0)) == trimmed } ?? false
            }
            return matches.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: matches)
        }
    }
}

/// A character's Unicode code, its HTML references (the named one, when HTML has a name for it, and the numeric one)
/// and how to type it on the keyboard layout in use, when it can be typed; each selectable.
private struct CharacterCodesGrid: View {
    let scalar: UInt32

    var body: some View {
        let layout = KeyboardLayout.current()
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Unicode").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(CharacterCodes.unicode(scalar)).monospaced().textSelection(.enabled)
            }
            GridRow {
                Text("HTML").foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let named = CharacterCodes.namedEntity(scalar) {
                        Text(named).monospaced().textSelection(.enabled)
                    }
                    Text(CharacterCodes.numericReference(scalar)).monospaced().textSelection(.enabled)
                }
            }
            if let layout, let keystroke = layout.keystroke(for: scalar) {
                GridRow {
                    Text("Keystroke").foregroundStyle(.secondary)
                    Text(keystroke.description).textSelection(.enabled)
                        .help("With the \(layout.name) keyboard layout")
                }
            }
        }
        .font(.callout)
    }
}
