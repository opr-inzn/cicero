import CiceroCore

/// What a font page lists under its styles for one face: the ligatures it makes and its characters by block.
nonisolated struct PageContent: Sendable {
    let ligatures: [LigatureGroup]
    let glyphs: [GlyphSection]
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

    /// Both together, so the page never shows one without the other.
    @concurrent
    private static func read(_ face: FontFace, coverage: CoverageIndex) async -> PageContent {
        async let ligatures = LigatureGroup.read(face)
        let scalars = await coverage.coverage(computing: face).scalars
        return PageContent(ligatures: await ligatures, glyphs: GlyphSection.sections(for: scalars))
    }
}
