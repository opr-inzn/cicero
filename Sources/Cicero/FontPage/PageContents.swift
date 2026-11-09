import CiceroCore
import CoreText

nonisolated struct PageContent: Sendable {
    let ligatures: [LigatureGroup]
    let glyphs: [GlyphSection]
    let characterCount: Int
    let ligatureCharacters: [CGGlyph: UInt32]
    let alternates: [UInt32: [FeatureAlternate]]
    // Glyphs are by ID, and a new version of the file can give those IDs to other glyphs.
    let generation: Int

    init(ligatures: [LigatureGroup], glyphs: [GlyphSection], alternates: [UInt32: [FeatureAlternate]], font: CTFont, generation: Int) {
        self.alternates = alternates
        self.generation = generation
        characterCount = glyphs.reduce(0) { $0 + $1.scalars.count }
        let made = Set(ligatures.flatMap { $0.ligatures.map(\.glyph) })
        var characters: [CGGlyph: UInt32] = [:]
        var listed: Set<UInt32> = []
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

    func isCurrent(for face: FontFace) -> Bool {
        generation == FontLoader.shared.generation(of: face.path)
    }
}

final class PageContents {
    private let coverage: CoverageIndex
    private var ready: [FaceID: PageContent] = [:]
    private var recent: [FaceID] = []
    private var loading: [FaceID: (generation: Int, task: Task<PageContent, Never>)] = [:]
    private var generation = 0
    private static let kept = 24

    init(coverage: CoverageIndex) {
        self.coverage = coverage
    }

    func content(of face: FontFace) -> PageContent? {
        ready[face.id].flatMap { $0.isCurrent(for: face) ? $0 : nil }
    }

    func prepare(_ face: FontFace) {
        if content(of: face) == nil { _ = task(for: face) }
    }

    func content(loading face: FontFace) async -> PageContent {
        if let content = content(of: face) {
            keep(content, for: face.id)
            return content
        }
        return await task(for: face).value
    }

    private func task(for face: FontFace) -> Task<PageContent, Never> {
        let version = FontLoader.shared.generation(of: face.path)
        if let under = loading[face.id], under.generation == version { return under.task }
        let coverage = coverage
        let started = generation
        let task = Task {
            let content = await Self.read(face, version: version, coverage: coverage)
            guard started == generation, loading[face.id]?.generation == version else { return content }
            loading[face.id] = nil
            keep(content, for: face.id)
            return content
        }
        loading[face.id] = (version, task)
        return task
    }

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

    @concurrent
    private static func read(_ face: FontFace, version: Int, coverage: CoverageIndex) async -> PageContent {
        async let ligatures = LigatureGroup.read(face)
        async let features = FeatureGlyph.read(face)
        async let alternates = FeatureAlternates.read(face)
        let font = FontLoader.shared.font(face, size: 12)
        let empty = EmptyGlyphs(font: font)
        let scalars = await coverage.coverage(computing: face).scalars
        let featureGlyphs = await features.filter { !empty.contains($0.glyph) }
        // Small capitals an older font keeps in private use too are listed as small capitals, not again as characters.
        let smallCaps = GlyphSection.privateUse(in: font, coverage: scalars,
                                                drawing: Set(featureGlyphs.filter { $0.group == .smallCaps }.map(\.glyph)))
        let grouped = Set(featureGlyphs.map(\.glyph))
        let listed = await alternates.compactMapValues { list in
            let left = list.filter { !grouped.contains($0.glyph) && !empty.contains($0.glyph) }
            return left.isEmpty ? nil : left
        }
        let drawn = await ligatures.compactMap { group in
            let left = group.ligatures.filter { !empty.contains($0.glyph) }
            return left.isEmpty ? nil : LigatureGroup(tag: group.tag, ligatures: left)
        }
        let sections = GlyphSection.sections(for: scalars, features: featureGlyphs,
                                             privateUse: GlyphSection.privateUseNames(in: font, coverage: scalars),
                                             leavingOut: { smallCaps.contains($0) || EmptyGlyphs.isInvisible($0) && empty.drawsNothing(for: $0) })
        return PageContent(ligatures: drawn, glyphs: sections, alternates: listed, font: font, generation: version)
    }
}

final class PageFeatures {
    private var ready: [FileFace: [FontFeatureGroup]] = [:]
    private var loading: [FileFace: Task<[FontFeatureGroup], Never>] = [:]

    func features(of face: FontFace) -> [FontFeatureGroup]? {
        ready[FileFace(face)]
    }

    func prepare(_ face: FontFace) {
        if features(of: face) == nil { _ = task(for: face) }
    }

    func features(loading face: FontFace) async -> [FontFeatureGroup] {
        if let features = features(of: face) { return features }
        return await task(for: face).value
    }

    private func task(for face: FontFace) -> Task<[FontFeatureGroup], Never> {
        let key = FileFace(face)
        if let under = loading[key] { return under }
        let task = Task {
            let features = await Task.detached(priority: .userInitiated) { FontFeatureGroup.load(for: face) }.value
            if loading[key] != nil {
                loading[key] = nil
                ready[key] = features
            }
            return features
        }
        loading[key] = task
        return task
    }

    func forget() {
        ready = [:]
        loading = [:]
    }
}
