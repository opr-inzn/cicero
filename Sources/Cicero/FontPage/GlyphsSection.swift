import AppKit
import CiceroCore
import SwiftUI

struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.glyphsTitleMoved) private var titleMoved
    let family: Family
    let face: FontFace
    let columns: Int
    let sections: [GlyphSection]
    let characterCount: Int
    let ligatures: [LigatureGroup]
    let ligatureCharacters: [CGGlyph: UInt32]
    let alternates: [UInt32: [FeatureAlternate]]
    let generation: Int
    @State private var query = ""
    @State private var open = OpenCell()
    @State private var covers = HeadingCovers()

    private typealias Cell = GlyphCell

    private struct Style {
        let face: FontFace
        let weight: Double
        let variations: [String: Double]
    }

    nonisolated static let cell: CGFloat = 52
    nonisolated static let spacing: CGFloat = 4
    nonisolated static let inset: CGFloat = 24
    static let titleGap: CGFloat = 56
    static let labelLine = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .callout)).rounded(.up)
    static let labelGap: CGFloat = 4
    static let runGap = labelLine - spacing - 2
    static let glyphSize: CGFloat = 26

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
            Spacer()
            TextField("Filter", text: $query, prompt: Text("Character, name or U+ code"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(TopRowKeeper.space)).minY } action: { [titleMoved] in titleMoved($0) }
        .padding(.horizontal, Self.inset)
        .padding(.top, Self.titleGap)
        .padding(.bottom, 4)
        if shown.isEmpty && shownLigatures.isEmpty {
            EmptyState(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                       description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else if isShort(shown, shownLigatures) {
            // A few rows in a stack of their own, one row of the page's lazy stack: under the tall title, the lazy stack's guesses at the heights of rows it hadn't placed swung back and forth, and it laid the page out again and again at full CPU.
            VStack(alignment: .leading, spacing: 0) {
                groups(shown, shownLigatures, style: style)
            }
            .environment(\.pinsHeadings, false)
        } else {
            groups(shown, shownLigatures, style: style)
        }
    }

    private func isShort(_ shown: [GlyphSection], _ shownLigatures: [LigatureGroup]) -> Bool {
        guard !query.isEmpty else { return false }
        let filter = Filter(query)
        var rows = shownLigatures.reduce(0) { $0 + ($1.ligatures.count + columns - 1) / columns }
        for section in shown {
            for run in section.labeledRuns(alternates: { shownAlternates(of: $0, filter) }) {
                rows += (run.cells.count + columns - 1) / columns
                if rows > Self.shortRows { return false }
            }
        }
        return true
    }

    private static let shortRows = 60

    @ViewBuilder
    private func groups(_ shown: [GlyphSection], _ shownLigatures: [LigatureGroup], style: Style) -> some View {
        let lead = GlyphSection.beforeLigatures(shown, of: sections)
        let ligatureCategory = lead > 0 ? shown[lead - 1].category : "Latin"
        let categories = shown.prefix(lead).map(\.category) + shownLigatures.map { _ in ligatureCategory } + shown.dropFirst(lead).map(\.category)
        let indexed = Array(shown.enumerated())
        ForEach(indexed.prefix(lead), id: \.element.id) { index, section in
            self.section(section, style: style, index: index, after: index > 0 ? shown[index - 1].category : nil, categories: categories)
        }
        if !shownLigatures.isEmpty {
            LigaturesSection(family: family.id, face: style.face, weight: style.weight, variations: style.variations,
                             columns: columns, groups: shownLigatures, characters: ligatureCharacters, generation: generation,
                             firstIndex: lead, category: ligatureCategory, after: lead > 0 ? shown[lead - 1].category : nil,
                             categories: categories)
        }
        ForEach(indexed.dropFirst(lead), id: \.element.id) { index, section in
            let previous = index > lead ? shown[index - 1].category : shownLigatures.isEmpty ? (lead > 0 ? shown[lead - 1].category : nil) : ligatureCategory
            self.section(section, style: style, index: index + shownLigatures.count, after: previous, categories: categories)
        }
        Color.clear.frame(height: 6)
    }

    static func bottom(of index: Int, in categories: [String]) -> CGFloat {
        index + 1 < categories.count && categories[index + 1] == categories[index] ? max(0, 22 - GlyphHeader.barHeight) : 18
    }

    private func section(_ section: GlyphSection, style: Style, index: Int, after previous: String?, categories: [String]) -> some View {
        let filter = Filter(query)
        let runs = section.labeledRuns { shownAlternates(of: $0, filter) }
        let rows = runs.flatMap { run in
            stride(from: 0, to: run.cells.count, by: columns).map { start in
                (label: start == 0 ? run.label : nil, cells: Array(run.cells[start ..< min(start + columns, run.cells.count)]))
            }
        }
        let total = runs.reduce(0) { $0 + $1.cells.count }
        let heading = GlyphHeading(index: index, category: section.category, name: section.name,
                                   detail: (section.kind.map { "(\($0)) " } ?? "") + "– \(total.plain)", after: previous,
                                   labelFollows: runs.first?.label != nil)
        return Section {
            // Rows of the page's lazy stack, all one height: it guesses unplaced rows' heights from placed ones, so a LazyVGrid per group re-laid it out at full CPU, and rows in stacks of their own drew other groups' rows after a long jump.
            ForEach(rows.indices, id: \.self) { row in
                let above = row == 0 ? 0 : Self.runGap
                GlyphRow(open: open, cells: rows[row].cells) { selected in
                    glyphRow(rows[row].cells, style: style, selected: selected)
                }
                .padding(.top, rows[row].label == nil ? 0 : above + Self.labelLine + Self.labelGap)
                .overlay(alignment: .topLeading) {
                    if let label = rows[row].label {
                        Text(label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: Self.labelLine)
                            .padding(.top, above)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { [most = GlyphHeader.headingHeight - GlyphHeader.line, top = GlyphHeader.labelledHeight] proxy in
                    guard row == 0, heading.labelFollows else { return 0 }
                    return min(most, max(0, top - proxy.frame(in: .scrollView).minY))
                } action: { [covers] in if row == 0 && heading.labelFollows { covers.covered[index] = $0 } }
                .padding(.horizontal, Self.inset)
                .padding(.bottom, row == rows.count - 1 ? Self.bottom(of: index, in: categories) : Self.spacing)
            }
        } header: {
            GlyphHeader(heading: heading, covers: covers)
        }
    }

    private var count: String {
        let characters = characterCount
        let ligatureCount = ligatures.reduce(0) { $0 + $1.ligatures.count }
        let featureGlyphs = sections.reduce(0) { total, section in
            total + (section.group == .tabularFigures ? section.glyphs.filter(\.isAlternate).count : section.glyphs.count)
        }
        let alternateCount = alternates.values.reduce(0) { $0 + $1.filter { !$0.isFigureStyle }.count } + featureGlyphs
        var parts = [characters == 1 ? "1 character" : "\(characters.plain) characters"]
        if ligatureCount > 0 { parts.append(ligatureCount == 1 ? "1 ligature" : "\(ligatureCount.plain) ligatures") }
        if alternateCount > 0 { parts.append(alternateCount == 1 ? "1 alternate" : "\(alternateCount.plain) alternates") }
        return parts.joined(separator: " · ")
    }

    private func glyphRow(_ cells: [Cell], style: Style, selected: Int?) -> GlyphGridRow {
        let font = FontLoader.shared.font(style.face, size: Self.glyphSize, weight: style.weight, variations: style.variations)
        let open = open
        let actions = GridRowActions(open: { open.cell = cells[$0] },
                                     details: { AnyView(details(cells[$0], style: style).environment(model).environment(preview)) },
                                     closed: { open.cell = nil }, menu: { copyMenu(cells[$0], style: style) },
                                     file: { dragFile(cells[$0], style: style) })
        return GlyphGridRow(cells: cells.map { gridCell($0, in: font) }, columns: columns, face: style.face, generation: generation,
                            weight: style.weight, variations: style.variations, selected: selected, actions: actions)
    }

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
                VStack(spacing: 0) {
                    Text(GlyphSection.name(of: glyph.character)?.capitalized ?? "Unnamed")
                    Text(zip(glyph.featureNames, glyph.featureTags).map { "\($0) (\($1))" }.joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: glyph.character)
                VStack {
                    let drawn = glyph.feature == "locl" ? "in \(glyph.featureName) text" : "with \(glyph.featureNames.listed()) on"
                    Button("Copy Character", systemImage: "doc.on.doc") { copyCharacter(cell, style: style) }
                        .help("Copies “\(Self.text(glyph.character))”, which shows like this when pasted into the text above, and elsewhere \(drawn)")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            case .alternate(let alternate):
                let names = alternate.listedNames
                GlyphImage(face: style.face, glyph: alternate.glyph, size: 96, weight: style.weight, variations: style.variations)
                    .frame(width: 160, height: 130)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                VStack(spacing: 0) {
                    Text(GlyphSection.name(of: alternate.character)?.capitalized ?? "Unnamed")
                    Text(zip(alternate.allFeatureNames, alternate.allFeatures).map { "\($0) (\($1))" }.joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                }
                .font(.callout).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: alternate.character)
                VStack {
                    Button("Copy Character", systemImage: "doc.on.doc") { copyCharacter(cell, style: style) }
                        .help("Copies “\(Self.text(alternate.character))”, which shows like this when pasted into the text above, and elsewhere with \(names) on")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: 260)
    }

    private func copyMenu(_ cell: Cell, style: Style) -> [GridMenuItem] {
        let scalar = Self.character(of: cell)
        return [
            GridMenuItem(title: "Copy Character") { copyCharacter(cell, style: style) },
            GridMenuItem(title: "Copy as Vector", isEnabled: outline(cell, style: style) != nil) { copyVector(cell, style: style) },
            GridMenuItem(title: "Copy Unicode") { copy(CharacterCodes.unicode(scalar), shown: CharacterCodes.unicode(scalar)) },
            GridMenuItem(title: "Copy HTML Entity") { copy(CharacterCodes.htmlEntity(scalar), shown: CharacterCodes.htmlEntity(scalar)) },
        ]
    }

    private func copyVectorButton(_ cell: Cell, style: Style) -> some View {
        Button("Copy as Vector", systemImage: "doc.on.doc") { copyVector(cell, style: style) }
            .disabled(outline(cell, style: style) == nil)
            .help("Copies the glyph’s outline, to paste into a design app as a shape you can edit, or as SVG code")
    }

    private func copy(_ text: String, shown: String) {
        Self.copy(text)
        CellPopover.shared.close()
        model.showToast("\(shown) copied to clipboard")
    }

    private func copyCharacter(_ cell: Cell, style: Style) {
        sampleClip(cell, style: style).copy()
        CellPopover.shared.close()
        model.showToast("\(Self.shown(Self.character(of: cell))) copied to clipboard")
    }

    private func sampleClip(_ cell: Cell, style: Style) -> SampleClip {
        let text = Self.text(Self.character(of: cell))
        let glyph: SampleGlyph? = switch cell {
        case .character: nil
        case .feature(let glyph):
            SampleGlyph(family: family.id, characters: text, face: style.face, glyph: glyph.glyph, features: glyph.featureTags)
        case .alternate(let alternate):
            SampleGlyph(family: family.id, characters: text, face: style.face, glyph: alternate.glyph,
                        features: alternate.drawnWith)
        }
        return SampleClip(text: text, glyph: glyph)
    }

    private func copyVector(_ cell: Cell, style: Style) {
        guard let outline = outline(cell, style: style) else { return NSSound.beep() }
        GlyphVectors.copy(outline, style: style.face.fullName, fallback: Self.fileFallback(cell), clip: sampleClip(cell, style: style))
        CellPopover.shared.close()
        model.showToast("\(Self.shown(Self.character(of: cell))) copied to clipboard as a vector")
    }

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

    private func outline(_ cell: Cell, style: Style) -> GlyphOutline? {
        let glyph = switch cell {
        case .character(let scalar): GlyphVectors.glyph(of: scalar, in: GlyphVectors.font(style.face, weight: style.weight, variations: style.variations))
        case .feature(let glyph): Optional(glyph.glyph)
        case .alternate(let alternate): Optional(alternate.glyph)
        }
        return GlyphVectors.outline(glyph, face: style.face, weight: style.weight, variations: style.variations)
    }

    private func dragItem(_ cell: Cell, style: Style) -> NSItemProvider {
        GlyphVectors.dragItem(outline(cell, style: style), style: style.face.fullName, fallback: Self.fileFallback(cell))
    }

    private func dragFile(_ cell: Cell, style: Style) -> URL? {
        GlyphVectors.dragFile(outline(cell, style: style), style: style.face.fullName, fallback: Self.fileFallback(cell))
    }

    private static func fileFallback(_ cell: Cell) -> String {
        switch cell {
        case .character(let scalar): CharacterCodes.unicode(scalar)
        case .feature(let glyph): ([CharacterCodes.unicode(glyph.character)] + glyph.featureTags).joined(separator: ".")
        case .alternate(let alternate): ([CharacterCodes.unicode(alternate.character)] + alternate.drawnWith).joined(separator: ".")
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func text(_ scalar: UInt32) -> String {
        Unicode.Scalar(scalar).map { String(Character($0)) } ?? ""
    }

    private func gridCell(_ cell: Cell, in font: CTFont) -> GridCell {
        switch cell {
        case .character(let scalar):
            if let glyph = GlyphVectors.glyph(of: scalar, in: font), Self.isCombining(scalar) || Self.takesNoRoom(glyph, in: font) {
                return GridCell(content: .glyph(glyph), label: Self.text(scalar))
            }
            return GridCell(content: .text(Self.text(scalar)), label: Self.text(scalar))
        case .feature(let glyph):
            return GridCell(content: .glyph(glyph.glyph), isAlternate: cell.isAlternate,
                            label: "\(Self.text(glyph.character)), \(glyph.featureNames.listed())")
        case .alternate(let alternate):
            return GridCell(content: .glyph(alternate.glyph), isAlternate: cell.isAlternate,
                            label: "\(Self.text(alternate.character)), \(alternate.listedNames)")
        }
    }

    @ViewBuilder
    private func character(_ scalar: UInt32, style: Style, size: CGFloat) -> some View {
        let font = FontLoader.shared.font(style.face, size: size, weight: style.weight, variations: style.variations)
        // A combining mark, or one a font keeps in private use, like a Thai tone mark shifted left, set on its own has nothing to sit on and shows nothing.
        if let glyph = GlyphVectors.glyph(of: scalar, in: font), Self.isCombining(scalar) || Self.takesNoRoom(glyph, in: font) {
            GlyphImage(face: style.face, glyph: glyph, size: size, weight: style.weight, variations: style.variations)
        } else {
            FontText(text: Self.text(scalar), face: style.face, size: size, weight: style.weight,
                     variations: style.variations)
                .foregroundStyle(Color.ink)
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

    private func shownAlternates(of scalar: UInt32, _ filter: Filter) -> [FeatureAlternate] {
        let all = alternates[scalar] ?? []
        guard !filter.isEmpty, !filter.matches(scalar) else { return all }
        return all.filter { alternate in zip(alternate.allFeatureNames, alternate.allFeatures).contains { filter.matches(feature: $0, tag: $1) } }
    }

    private func filtered(_ sections: [GlyphSection]) -> [GlyphSection] {
        let filter = Filter(query)
        guard !filter.isEmpty else { return sections }
        return sections.compactMap { section in
            let characters = section.scalars.filter { filter.matches($0) || !shownAlternates(of: $0, filter).isEmpty }
            let glyphs = section.glyphs.filter { glyph in
                filter.matches(glyph.character) || zip(glyph.featureNames, glyph.featureTags).contains { filter.matches(feature: $0, tag: $1) }
            }
            return characters.isEmpty && glyphs.isEmpty ? nil : GlyphSection(group: section.group, scalars: characters, glyphs: glyphs)
        }
    }

    private func filtered(_ groups: [LigatureGroup]) -> [LigatureGroup] {
        let filter = Filter(query)
        guard !filter.isEmpty else { return groups }
        let trimmed = filter.trimmed
        return groups.compactMap { group in
            let matches = group.ligatures.filter { ligature in
                let own = ligatureCharacters[ligature.glyph]
                return ligature.text.localizedCaseInsensitiveContains(trimmed)
                    || filter.code.map { ligature.characters.contains($0) || own == $0 } ?? false
                    || own.flatMap(Unicode.Scalar.init).map { String(Character($0)) == trimmed } ?? false
            }
            return matches.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: matches)
        }
    }
}

@Observable
final class OpenCell {
    var cell: GlyphCell?
}

private struct GlyphRow: View {
    let open: OpenCell
    let cells: [GlyphCell]
    let row: (_ selected: Int?) -> GlyphGridRow

    var body: some View {
        row(open.cell.flatMap { cells.firstIndex(of: $0) })
    }
}

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
