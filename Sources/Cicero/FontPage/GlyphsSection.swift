import AppKit
import CiceroCore
import SwiftUI

struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    @Environment(\.glyphsTitle) private var title
    let family: Family
    let face: FontFace
    let columns: Int
    let sections: [GlyphSection]
    let glyphCount: Int
    let alternateCount: Int
    let ligatures: [LigatureGroup]
    let ligatureCharacters: [CGGlyph: UInt32]
    let alternates: [UInt32: [FeatureAlternate]]
    let generation: Int
    @Binding var query: String
    let open: OpenCell

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
    static let popoverWidth: CGFloat = 280
    static let metricsHeight: CGFloat = 190

    struct RowID: Hashable {
        let group: GlyphGroup
        let row: Int
    }

    func row(of scalar: UInt32) -> RowID? {
        let filter = Filter(query)
        for section in filtered(sections) {
            var row = 0
            for run in section.labeledRuns(alternates: { shownAlternates(of: $0, filter) }) {
                if let index = run.cells.firstIndex(of: .character(scalar)) { return RowID(group: section.group, row: row + index / columns) }
                row += (run.cells.count + columns - 1) / columns
            }
        }
        return nil
    }

    nonisolated static func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + spacing) / (cell + spacing)))
    }

    var body: some View {
        let (chosen, weight) = model.previewStyle(of: family)
        let style = chosen.id == face.id ? Style(face: face, weight: weight, variations: model.variations(for: family, face: face.id))
            : Style(face: face, weight: face.styleWeight, variations: [:])
        let shown = filtered(sections)
        let shownLigatures = filtered(ligatures)
        let items = items(shown, shownLigatures)
        let lifted = Set(items.indices.filter { items[$0].isLocalizedForms })
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
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(TopRowKeeper.space)).minY } action: { [title] y in if title?.y != y { title?.y = y } }
        .padding(.horizontal, Self.inset)
        .padding(.top, Self.titleGap)
        .padding(.bottom, lifted.contains(0) ? 4 - GlyphHeader.labelLift : 4)
        if shown.isEmpty && shownLigatures.isEmpty {
            EmptyState(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                       description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else if isShort(shown, shownLigatures) {
            // In one stack: as rows of the page's lazy stack under the tall title, a few rows made it lay the page out again and again at full CPU.
            VStack(alignment: .leading, spacing: 0) {
                groups(items, style: style, lifted: lifted)
            }
            .environment(\.pinsHeadings, false)
        } else {
            groups(items, style: style, lifted: lifted)
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

    private enum Item: Identifiable {
        case section(GlyphSection)
        case ligatures(LigatureGroup, category: String)

        var id: String {
            switch self {
            case .section(let section): "section \(section.id)"
            case .ligatures(let group, _): "ligatures \(group.id)"
            }
        }

        var category: String {
            switch self {
            case .section(let section): section.category
            case .ligatures(_, let category): category
            }
        }

        var isLocalizedForms: Bool {
            if case .section(let section) = self { section.group.isLocalizedForms } else { false }
        }
    }

    private func items(_ shown: [GlyphSection], _ shownLigatures: [LigatureGroup]) -> [Item] {
        let lead = GlyphSection.beforeLigatures(shown, of: sections)
        let common = lead > 0 ? shown[lead - 1].category : "Latin"
        var items = shown.map(Item.section)
        let others = shownLigatures.filter { $0.script == nil }
        items.insert(contentsOf: others.map { .ligatures($0, category: common) }, at: lead)
        var scripts: [String] = []
        for script in shownLigatures.compactMap(\.script) where !scripts.contains(script) { scripts.append(script) }
        for script in scripts {
            let own = items.indices.filter { if case .section(let section) = items[$0] { section.group.scriptName == script } else { false } }
            let after = own.first { index in
                guard case .section(let section) = items[index], case .scriptPart(_, let part) = section.group else { return false }
                return part.rawValue >= GlyphGroup.ScriptPart.localizedForms.rawValue
            }
            let at = after ?? own.last.map { $0 + 1 } ?? lead + others.count
            let groups = shownLigatures.filter { $0.script == script }
            items.insert(contentsOf: groups.map { .ligatures($0, category: script) }, at: at)
        }
        return items
    }

    @ViewBuilder
    private func groups(_ items: [Item], style: Style, lifted: Set<Int>) -> some View {
        let categories = items.map(\.category)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let previous = index > 0 ? categories[index - 1] : nil
            switch item {
            case .section(let section):
                self.section(section, style: style, index: index, after: previous, categories: categories, lifted: lifted)
            case .ligatures(let group, let category):
                LigaturesSection(family: family.id, face: style.face, weight: style.weight, variations: style.variations,
                                 columns: columns, groups: [group], characters: ligatureCharacters, generation: generation,
                                 firstIndex: index, category: category, after: previous, categories: categories, lifted: lifted)
            }
        }
        Color.clear.frame(height: 6)
    }

    static func bottom(of index: Int, in categories: [String], lifted: Set<Int>) -> CGFloat {
        let bottom = index + 1 < categories.count && categories[index + 1] == categories[index] ? max(0, 22 - GlyphHeader.barHeight) : 18
        return lifted.contains(index + 1) ? bottom - GlyphHeader.labelLift : bottom
    }

    private func section(_ section: GlyphSection, style: Style, index: Int, after previous: String?, categories: [String], lifted: Set<Int>) -> some View {
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
                                   labelFollows: section.group.isLocalizedForms)
        return Section {
            // Not a LazyVGrid per group, which made the page's lazy stack lay it out again at full CPU, nor a stack per group, which drew other groups' rows after a long jump.
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
                .padding(.horizontal, Self.inset)
                .padding(.bottom, row == rows.count - 1 ? Self.bottom(of: index, in: categories, lifted: lifted) : Self.spacing)
                .id(RowID(group: section.group, row: row))
            }
        } header: {
            GlyphHeader(heading: heading)
        }
    }

    private var count: String {
        let ligatureCount = ligatures.reduce(0) { $0 + $1.ligatures.count }
        var parts = [glyphCount == 1 ? "1 glyph" : "\(glyphCount.plain) glyphs"]
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
                Group {
                    if let glyph = GlyphVectors.glyph(of: scalar, in: GlyphVectors.font(style.face, weight: style.weight, variations: style.variations)) {
                        GlyphMetrics(face: style.face, glyph: glyph, characters: [scalar], weight: style.weight, variations: style.variations)
                            .frame(height: Self.metricsHeight)
                    } else {
                        character(scalar, style: style, size: 96)
                            .frame(minHeight: 130)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onDrag { dragItem(cell, style: style) }
                Text(GlyphSection.shownName(of: scalar) ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                CharacterCodesGrid(scalar: scalar)
                VStack {
                    Button("Copy Character", systemImage: "doc.on.doc") { copy(Self.text(scalar), shown: Self.shown(scalar)) }
                        .help("Copies “\(Self.text(scalar))”")
                    copyVectorButton(cell, style: style)
                }
                .buttonStyle(StillPushButtonStyle())
            case .feature(let glyph):
                GlyphMetrics(face: style.face, glyph: glyph.glyph, characters: [glyph.character], weight: style.weight, variations: style.variations)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.metricsHeight)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                VStack(spacing: 0) {
                    Text(GlyphSection.shownName(of: glyph.character) ?? "Unnamed")
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
                GlyphMetrics(face: style.face, glyph: alternate.glyph, characters: [alternate.character], weight: style.weight, variations: style.variations)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.metricsHeight)
                    .contentShape(.rect)
                    .onDrag { dragItem(cell, style: style) }
                VStack(spacing: 0) {
                    Text(GlyphSection.shownName(of: alternate.character) ?? "Unnamed")
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
        .frame(width: Self.popoverWidth)
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
            return GlyphSection.shownName(of: scalar) ?? CharacterCodes.unicode(scalar)
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
                .minimumScaleFactor(0.25)
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
            return matches.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: matches, script: group.script)
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
