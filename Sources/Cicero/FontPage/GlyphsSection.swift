import AppKit
import CiceroCore
import SwiftUI

/// Every character a style draws, and the glyphs its features draw in place of characters', like tabular figures, by
/// group (see `GlyphGroup`), the ligatures it makes, by feature, in the Ligatures group's place, under headers like the
/// groups'; with a filter by character, Unicode name or U+ code that takes in the ligatures and feature glyphs too.
/// The alternates its features offer, like a stylistic set's, follow the characters they're for, marked with a grey dot;
/// figures go in rows by kind instead, lining, old-style, other alternates, then signs (see `GlyphSection.runs`).
/// Several views in a row, so each group's cells are rows of the page's lazy stack.
struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    /// The style whose glyphs these are: the text's, or the one before it while its glyphs are read.
    let face: FontFace
    /// Cells per row, from the page's width.
    let columns: Int
    /// The style's characters, but those listed as ligatures, and its feature glyphs.
    let sections: [GlyphSection]
    /// All of them.
    let characterCount: Int
    let ligatures: [LigatureGroup]
    /// The character a ligature's glyph is too, like U+FB01 for ﬁ.
    let ligatureCharacters: [CGGlyph: UInt32]
    /// The glyphs features offer in place of characters', by character.
    let alternates: [UInt32: [FeatureAlternate]]
    @State private var query = ""
    @State private var popover: Cell?

    private typealias Cell = GlyphCell

    /// The style the page's text is set in, chosen in its Style menu or the one for the preview weight, at its
    /// weight and with its axes as moved: the glyphs are its.
    private struct Style {
        let face: FontFace
        let weight: Double
        let variations: [String: Double]
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
        let (chosen, weight) = model.previewStyle(of: family, weight: preview.weight)
        let style = chosen.id == face.id ? Style(face: face, weight: weight, variations: model.variations(for: family, face: face.id))
            : Style(face: face, weight: face.styleWeight, variations: [:])
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
        // Well clear of the styles above, and close to the groups it heads.
        .padding(.top, 56)
        .padding(.bottom, 4)
        if shown.isEmpty && shownLigatures.isEmpty {
            ContentUnavailableView(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                                   description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else {
            let lead = GlyphSection.beforeLigatures(shown, of: sections)
            ForEach(shown.prefix(lead)) { section in
                self.section(section, style: style)
            }
            // In the Ligatures group's place, after its characters, like ﬀ, that no feature makes, or after the one
            // script a font without Latin letters starts with.
            if !shownLigatures.isEmpty {
                LigaturesSection(face: style.face, weight: style.weight, variations: style.variations, columns: columns, groups: shownLigatures,
                                 characters: ligatureCharacters)
            }
            ForEach(shown.dropFirst(lead)) { section in
                self.section(section, style: style)
            }
            Color.clear.frame(height: 6)
        }
    }

    private func section(_ section: GlyphSection, style: Style) -> some View {
        let filter = Filter(query)
        // Figures in runs, lining, old-style and so on, each starting a row (see `GlyphSection.runs`).
        let runs = section.runs { shownAlternates(of: $0, filter) }
        let rows = runs.flatMap { run in
            stride(from: 0, to: run.count, by: columns).map { run[$0 ..< min($0 + columns, run.count)] }
        }
        let total = runs.reduce(0) { $0 + $1.count }
        return Section {
            // Rows of the page's stack, not a LazyVGrid per group in it. The stack guesses the height of groups it
            // hasn't placed from those it has, and groups run from one row to hundreds, so every correction shifted
            // the page and changed which groups were placed: it re-laid itself out at full CPU. Rows of fixed cells
            // are all one height, so the guesses are right.
            ForEach(rows.indices, id: \.self) { row in
                glyphRow(rows[row], style: style)
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, row == rows.count - 1 ? 18 : Self.spacing)
            }
        } header: {
            HStack(spacing: 6) {
                Text(section.title).font(.headline)
                Text("— \(total.formatted())").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 4)
        }
    }

    /// "124 characters", and the ligatures and alternates when there are any: "124 characters · 3 ligatures · 40 alternates".
    private var count: String {
        let characters = characterCount
        let ligatureCount = ligatures.reduce(0) { $0 + $1.ligatures.count }
        let alternateCount = alternates.values.reduce(0) { $0 + $1.count }
        var parts = [characters == 1 ? "1 character" : "\(characters.formatted()) characters"]
        if ligatureCount > 0 { parts.append(ligatureCount == 1 ? "1 ligature" : "\(ligatureCount.formatted()) ligatures") }
        if alternateCount > 0 { parts.append(alternateCount == 1 ? "1 alternate" : "\(alternateCount.formatted()) alternates") }
        return parts.joined(separator: " · ")
    }

    /// One popover per row, pointing at the clicked cell, rather than one per cell: each is worked out
    /// again whenever the page updates. The cells share out the row's width, so they reach the page's edge
    /// whatever it is, without the page drawing them again as it changes; a short last row keeps their width.
    private func glyphRow(_ cells: ArraySlice<Cell>, style: Style) -> some View {
        let column = popover.flatMap { cells.firstIndex(of: $0) }.map { $0 - cells.startIndex }
        // The clicked cell's bottom middle, within two points: the cells are as wide as the row allows.
        let anchor = UnitPoint(x: (CGFloat(column ?? 0) + 0.5) / CGFloat(columns), y: 1)
        return HStack(spacing: Self.spacing) {
            ForEach(cells, id: \.self) { cell in
                glyph(cell, style: style)
            }
            ForEach(cells.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: Self.cell)
            }
        }
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .point(anchor)) {
            if let popover {
                details(popover, style: style)
            }
        }
    }

    /// A character's name and codes, and buttons that copy it and its glyph's outline; for a feature's glyph, the
    /// character's, and the feature's name.
    private func details(_ cell: Cell, style: Style) -> some View {
        VStack(spacing: 10) {
            switch cell {
            case .character(let scalar):
                character(scalar, style: style, size: 96)
                    .frame(minWidth: 160, minHeight: 130)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                Text(GlyphSection.name(of: scalar)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: scalar)
                // Stacked: side by side they're wider than the popover.
                VStack {
                    Button("Copy Character", systemImage: "doc.on.doc") { copy(Self.text(scalar), shown: Self.shown(scalar)) }
                        .help("Copies “\(Self.text(scalar))”")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            case .feature(let glyph):
                GlyphImage(face: style.face, glyph: glyph.glyph, size: 96, weight: style.weight, variations: style.variations)
                    .frame(width: 160, height: 130)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                Text(GlyphSection.name(of: glyph.character)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                // "Tabular Figures (tnum)", and "Old-Style Figures (onum)" under it for a tabular old-style figure.
                Text(zip(glyph.featureNames, glyph.featureTags).map { "\($0) (\($1))" }.joined(separator: "\n"))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: glyph.character)
                // The glyph has no code of its own: what's copied is the character, which the font draws like this
                // where the feature is on.
                VStack {
                    Button("Copy Character", systemImage: "doc.on.doc") { copy(Self.text(glyph.character), shown: Self.shown(glyph.character)) }
                        .help("Copies “\(Self.text(glyph.character))”, which this font draws like this with \(glyph.featureNames.formatted(.list(type: .and))) on")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            case .alternate(let alternate):
                let names = alternate.featureNames.formatted(.list(type: .or))
                GlyphImage(face: style.face, glyph: alternate.glyph, size: 96, weight: style.weight, variations: style.variations)
                    .frame(width: 160, height: 130)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                Text(GlyphSection.name(of: alternate.character)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                // "Single-storey a (ss07)"
                Text(zip(alternate.featureNames, alternate.features).map { "\($0) (\($1))" }.joined(separator: "\n"))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: alternate.character)
                VStack {
                    Button("Copy Character", systemImage: "doc.on.doc") { copy(Self.text(alternate.character), shown: Self.shown(alternate.character)) }
                        .help("Copies “\(Self.text(alternate.character))”, which this font draws like this with \(names) on")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: 260)
    }

    /// Copy Character, Copy as Vector, Copy Unicode and Copy HTML Entity, for a cell's right-click menu: a feature's
    /// glyph copies the character it's drawn for, as text, and its own shape as a vector.
    @ViewBuilder
    private func copyMenu(_ cell: Cell, style: Style) -> some View {
        let scalar = Self.character(of: cell)
        Button("Copy Character", systemImage: "doc.on.clipboard") { copy(Self.text(scalar), shown: Self.shown(scalar)) }
        // Not greyed out for a glyph without an outline: the menus are made with every cell, and the outline isn't.
        Button("Copy as Vector", systemImage: "doc.on.clipboard") { copyVector(cell, style: style) }
        Button("Copy Unicode", systemImage: "doc.on.clipboard") { copy(CharacterCodes.unicode(scalar), shown: CharacterCodes.unicode(scalar)) }
        Button("Copy HTML Entity", systemImage: "doc.on.clipboard") { copy(CharacterCodes.htmlEntity(scalar), shown: CharacterCodes.htmlEntity(scalar)) }
    }

    /// Copy as Vector, under Copy Character in a glyph's popover.
    private func copyVectorButton(_ cell: Cell, style: Style) -> some View {
        Button("Copy as Vector", systemImage: "doc.on.doc") { copyVector(cell, style: style) }
            .disabled(outline(cell, style: style) == nil)
            .help("Copies the glyph’s outline, to paste into a design app as a shape you can edit, or as SVG code")
    }

    /// Puts text on the clipboard, closes the popover and says what was copied, at the bottom of the window, as when
    /// fonts are turned on: "“g” copied to clipboard".
    private func copy(_ text: String, shown: String) {
        Self.copy(text)
        popover = nil
        model.showToast("\(shown) copied to clipboard")
    }

    /// The glyph's outline, as for text; a beep for a glyph without one.
    private func copyVector(_ cell: Cell, style: Style) {
        guard let outline = outline(cell, style: style) else { return NSSound.beep() }
        GlyphVectors.copy(outline, style: style.face.fullName, fallback: Self.fileFallback(cell))
        popover = nil
        model.showToast("\(Self.shown(Self.character(of: cell))) copied to clipboard as a vector")
    }

    /// A character as a toast names it: in quotes, a mark on a dotted circle, as it has nothing to sit on, and one you
    /// can't see, like a space, by its name.
    static func shown(_ scalar: UInt32) -> String {
        guard let character = Unicode.Scalar(scalar) else { return CharacterCodes.unicode(scalar) }
        switch character.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format:
            return GlyphSection.name(of: scalar)?.capitalized ?? CharacterCodes.unicode(scalar)
        case .nonspacingMark, .enclosingMark, .spacingMark:
            return "“\u{25CC}\(Character(character))”"
        default:
            return "“\(Character(character))”"
        }
    }

    private static func character(of cell: Cell) -> UInt32 {
        switch cell {
        case .character(let scalar): scalar
        case .feature(let glyph): glyph.character
        case .alternate(let alternate): alternate.character
        }
    }

    /// The cell's glyph as a vector, in the page's style: the one the cell shows.
    private func outline(_ cell: Cell, style: Style) -> GlyphOutline? {
        let glyph = switch cell {
        case .character(let scalar): GlyphVectors.glyph(of: scalar, in: GlyphVectors.font(style.face, weight: style.weight, variations: style.variations))
        case .feature(let glyph): Optional(glyph.glyph)
        case .alternate(let alternate): Optional(alternate.glyph)
        }
        return GlyphVectors.outline(glyph, face: style.face, weight: style.weight, variations: style.variations)
    }

    /// The cell's glyph as an SVG file, named after the style and the glyph.
    private func dragItem(_ cell: Cell, style: Style) -> NSItemProvider {
        GlyphVectors.dragItem(outline(cell, style: style), style: style.face.fullName, fallback: Self.fileFallback(cell))
    }

    /// What a glyph's file is called after when the font doesn't name the glyph: its character's code, and the feature
    /// that draws it, as in "Inter Regular U+0061.ss01.svg".
    private static func fileFallback(_ cell: Cell) -> String {
        switch cell {
        case .character(let scalar): CharacterCodes.unicode(scalar)
        case .feature(let glyph): "\(CharacterCodes.unicode(glyph.character)).\(glyph.feature)"
        case .alternate(let alternate): "\(CharacterCodes.unicode(alternate.character)).\(alternate.features.first ?? "alt")"
        }
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

    private func glyph(_ cell: Cell, style: Style) -> some View {
        Group {
            switch cell {
            case .character(let scalar): character(scalar, style: style, size: Self.glyphSize)
            case .feature(let glyph):
                GlyphImage(face: style.face, glyph: glyph.glyph, size: Self.glyphSize, weight: style.weight, variations: style.variations)
            case .alternate(let alternate):
                GlyphImage(face: style.face, glyph: alternate.glyph, size: Self.glyphSize, weight: style.weight, variations: style.variations)
            }
        }
        .frame(minWidth: Self.cell, maxWidth: .infinity, minHeight: Self.cell, maxHeight: Self.cell)
        .background(.quaternary.opacity(popover == cell ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
        // An alternate, after the character's own glyph; grey, as colours stand for tags.
        .overlay(alignment: .topTrailing) {
            if case .alternate = cell {
                Circle().fill(.secondary).frame(width: 6, height: 6).padding(5)
            }
        }
        .contentShape(.rect)
        .onTapGesture { popover = cell }
        // Out of the page as an SVG file, or into a design app as a vector.
        .onDrag { dragItem(cell, style: style) }
        // VoiceOver opens the popover as a click does.
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { popover = cell }
        .contextMenu { copyMenu(cell, style: style) }
    }

    /// A character set in the font. One that takes no room of its own is drawn from its outline instead: a mark that
    /// combines with the character before it (an acute, a cedilla), or one a font keeps in private use, like a Thai tone
    /// mark shifted left, set on its own has nothing to sit on and showed nothing.
    @ViewBuilder
    private func character(_ scalar: UInt32, style: Style, size: CGFloat) -> some View {
        let font = FontLoader.shared.font(style.face, size: size, weight: style.weight, variations: style.variations)
        if let glyph = GlyphVectors.glyph(of: scalar, in: font), Self.isCombining(scalar) || Self.takesNoRoom(glyph, in: font) {
            GlyphImage(face: style.face, glyph: glyph, size: size, weight: style.weight, variations: style.variations)
        } else {
            FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: style.face, size: size, weight: style.weight,
                     variations: style.variations)
        }
    }

    private static func takesNoRoom(_ glyph: CGGlyph, in font: CTFont) -> Bool {
        var glyph = glyph
        return CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1) == 0
    }

    private static func isCombining(_ scalar: UInt32) -> Bool {
        switch Unicode.Scalar(scalar)?.properties.generalCategory {
        case .nonspacingMark, .enclosingMark: true
        default: false
        }
    }

    /// What's typed into the filter: a character, part of its Unicode name or a feature's, a U+ code or a feature's tag.
    private struct Filter {
        let trimmed: String
        let lower: String
        let scalars: Set<UInt32>
        let code: UInt32?

        init(_ query: String) {
            trimmed = query.trimmingCharacters(in: .whitespaces)
            lower = trimmed.lowercased()
            scalars = Set(trimmed.unicodeScalars.map(\.value))
            code = UInt32(trimmed.uppercased().replacingOccurrences(of: "U+", with: "").replacingOccurrences(of: "0X", with: ""), radix: 16)
        }

        var isEmpty: Bool { trimmed.isEmpty }

        func matches(_ scalar: UInt32) -> Bool {
            scalars.contains(scalar) || scalar == code
                || (trimmed.count > 1 && (GlyphSection.name(of: scalar)?.lowercased().contains(lower) ?? false))
        }

        func matches(feature name: String, tag: String) -> Bool {
            trimmed.count > 1 && (name.lowercased().contains(lower) || tag == lower)
        }
    }

    /// A character's alternates the filter lets through: all of them when it finds the character, else those of the
    /// features it finds.
    private func shownAlternates(of scalar: UInt32, _ filter: Filter) -> [FeatureAlternate] {
        let all = alternates[scalar] ?? []
        guard !filter.isEmpty, !filter.matches(scalar) else { return all }
        return all.filter { alternate in zip(alternate.featureNames, alternate.features).contains { filter.matches(feature: $0, tag: $1) } }
    }

    private func filtered(_ sections: [GlyphSection]) -> [GlyphSection] {
        let filter = Filter(query)
        guard !filter.isEmpty else { return sections }
        return sections.compactMap { section in
            // A character with an alternate the filter finds, which follows it; a feature's glyph by its character, or
            // the feature's name or tag.
            let characters = section.scalars.filter { filter.matches($0) || !shownAlternates(of: $0, filter).isEmpty }
            let glyphs = section.glyphs.filter { glyph in
                filter.matches(glyph.character) || zip(glyph.featureNames, glyph.featureTags).contains { filter.matches(feature: $0, tag: $1) }
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

/// A character's Unicode code and its HTML references (the named one, when HTML has a name for it, and the numeric
/// one), each selectable.
private struct CharacterCodesGrid: View {
    let scalar: UInt32

    var body: some View {
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
        }
        .font(.callout)
    }
}
