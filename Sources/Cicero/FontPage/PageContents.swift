import CiceroCore
import CoreText

/// What a font page lists under its styles for one face: its characters and the glyphs its features draw, by group,
/// and the ligatures it makes. A character
/// whose glyph a ligature feature makes, like ﬁ, which fonts usually give U+FB01 (Alphabetic Presentation Forms) too, is
/// listed once, as a ligature, which says the character.
nonisolated struct PageContent: Sendable {
    let ligatures: [LigatureGroup]
    /// The characters and feature glyphs by group, but characters listed as ligatures.
    let glyphs: [GlyphSection]
    /// Every character the face draws, those listed as ligatures included.
    let characterCount: Int
    /// The character a ligature's glyph is too, by glyph.
    let ligatureCharacters: [CGGlyph: UInt32]
    /// The glyphs features offer in place of characters', by character.
    let alternates: [UInt32: [FeatureAlternate]]

    init(ligatures: [LigatureGroup], glyphs: [GlyphSection], alternates: [UInt32: [FeatureAlternate]], font: CTFont) {
        self.alternates = alternates
        characterCount = glyphs.reduce(0) { $0 + $1.scalars.count }
        let made = Set(ligatures.flatMap { $0.ligatures.map(\.glyph) })
        var characters: [CGGlyph: UInt32] = [:]
        var listed: Set<UInt32> = []
        // The characters whose glyph a ligature is (the lowest, for its popover, where several share one); none to look
        // for without ligatures.
        for scalar in made.isEmpty ? [] : glyphs.flatMap(\.scalars).reversed() {
            guard let character = Unicode.Scalar(scalar) else { continue }
            var units = Array(String(Character(character)).utf16)
            var glyph = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(font, &units, &glyph, units.count), made.contains(glyph[0]) {
                characters[glyph[0]] = scalar
                listed.insert(scalar)
            }
        }
        self.ligatures = ligatures
        self.glyphs = listed.isEmpty ? glyphs : glyphs.compactMap { section in
            let left = section.scalars.filter { !listed.contains($0) }
            return left.isEmpty && section.glyphs.isEmpty ? nil : GlyphSection(group: section.group, scalars: left, glyphs: section.glyphs)
        }
        ligatureCharacters = characters
    }
}

/// Font pages' ligatures and characters, worked out off the main thread and kept for the faces shown last. The
/// browser starts on a family as soon as it's selected, so the page a double-click or Return opens has them in its
/// first frame instead of filling in a section at a time.
final class PageContents {
    private let coverage: CoverageIndex
    private var ready: [FaceID: PageContent] = [:]
    /// The faces in `ready`, least recently used first.
    private var recent: [FaceID] = []
    private var loading: [FaceID: Task<PageContent, Never>] = [:]
    /// Bumped when files change, so what was read from an old version of one is never kept.
    private var generation = 0
    private static let kept = 24

    init(coverage: CoverageIndex) {
        self.coverage = coverage
    }

    /// nil until worked out.
    func content(of face: FontFace) -> PageContent? {
        ready[face.id]
    }

    /// Starts on a face's content, unless it's ready or under way.
    func prepare(_ face: FontFace) {
        if ready[face.id] == nil { _ = task(for: face) }
    }

    func content(loading face: FontFace) async -> PageContent {
        if let content = ready[face.id] {
            keep(content, for: face.id)
            return content
        }
        return await task(for: face).value
    }

    private func task(for face: FontFace) -> Task<PageContent, Never> {
        if let task = loading[face.id] { return task }
        let coverage = coverage
        let started = generation
        let task = Task {
            let content = await Self.read(face, coverage: coverage)
            guard started == generation else { return content }
            loading[face.id] = nil
            keep(content, for: face.id)
            return content
        }
        loading[face.id] = task
        return task
    }

    /// Files a scan found changed: what was read from them goes, and so does anything still being read.
    func forget(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        generation += 1
        loading = [:]
        for id in recent where paths.contains(id.path) { ready[id] = nil }
        recent.removeAll { paths.contains($0.path) }
    }

    private func keep(_ content: PageContent, for id: FaceID) {
        ready[id] = content
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > Self.kept { ready[recent.removeFirst()] = nil }
    }

    /// Both together, so the page never shows one without the other. Glyphs that draw nothing, like a trial font's
    /// empty ones, are left out: a character's, a feature's, an alternate or a ligature.
    @concurrent
    private static func read(_ face: FontFace, coverage: CoverageIndex) async -> PageContent {
        async let ligatures = LigatureGroup.read(face)
        async let features = FeatureGlyph.read(face)
        async let alternates = FeatureAlternates.read(face)
        let font = FontLoader.shared.font(face, size: 12)
        let empty = EmptyGlyphs(font: font)
        let scalars = await coverage.coverage(computing: face).scalars
        let featureGlyphs = await features.filter { !empty.contains($0.glyph) }
        // Those in groups of their own, like tabular figures, aren't listed again after their characters.
        let grouped = Set(featureGlyphs.map(\.glyph))
        let listed = await alternates.compactMapValues { list in
            let left = list.filter { !grouped.contains($0.glyph) && !empty.contains($0.glyph) }
            return left.isEmpty ? nil : left
        }
        let drawn = await ligatures.compactMap { group in
            let left = group.ligatures.filter { !empty.contains($0.glyph) }
            return left.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: left)
        }
        // The coverage has only the characters the font draws, and those with nothing to draw that it has; of those, the
        // page shows the ones it draws something for anyway.
        let sections = GlyphSection.sections(for: scalars, features: featureGlyphs,
                                             privateUse: GlyphSection.privateUseGroups(in: font, coverage: scalars),
                                             leavingOut: { EmptyGlyphs.isInvisible($0) && empty.drawsNothing(for: $0) })
        return PageContent(ligatures: drawn, glyphs: sections, alternates: listed, font: font)
    }
}
