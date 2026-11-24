import Foundation

public struct SimilarFonts: Sendable {
    private let ids: [String]
    private let positions: [String: Int]
    private let values: [Float]
    private let embeddings: [Float]
    private let dimensions: Int
    private let tagVectors: [Float]
    private let tagCount: Int
    private let themeIndices: [Int]
    private let classifications: [String?]
    private let sizes: [OpticalSize?]
    private let designs: [String]
    private let styleDesigns: [String]
    private let styleRows: [[SearchQuery.Style: Int]]
    private let regularKinds: [SearchQuery.Style]
    private let neighborRows: [[Int]]
    private let italicOnly: [Bool]
    private let rounded: [Bool]
    private let plainDesigns: [String]
    private let stencil: [Bool]
    private let plainStencilDesigns: [String]
    private let outline: [Bool]
    private let plainOutlineDesigns: [String]
    private let allCaps: [Bool]
    private let decorative: [Bool]
    private let roots: [String]
    private let scales: [Float]
    private let weights: [Float]
    private let embeddingWeight: Float
    private let tagWeight: Float
    private let otherClassification: Float
    private let sameRootPenalty: Float
    private let decorativeClassifications: Set<String>

    private static let measures = LetterMeasurements.Measure.allCases.count

    public static let weights: [LetterMeasurements.Measure: Float] = [
        .xHeight: 1.5, .ascender: 0.5, .descender: 0.5, .weight: 2.5, .contrast: 2, .stress: 1, .width: 6, .capitalWidth: 3,
        .roundWidth: 3, .spacing: 0.5, .slant: 1.5, .serifLength: 2.5, .serifThickness: 1, .aperture: 1,
        .squareness: 0.75, .doubleStoryA: 1, .doubleStoryG: 0.75, .monospaced: 2,
    ]

    public static let steps: [LetterMeasurements.Measure: Float] = [
        .xHeight: 0.04, .ascender: 0.03, .descender: 0.04, .weight: 0.025, .contrast: 0.1, .stress: 0.15, .width: 0.08,
        .capitalWidth: 0.07, .roundWidth: 0.07, .spacing: 0.05, .slant: 0.07, .serifLength: 0.03, .serifThickness: 0.03,
        .aperture: 0.04, .squareness: 0.02, .doubleStoryA: 0.5, .doubleStoryG: 0.5, .monospaced: 0.5,
    ]

    public static let embeddingWeight: Float = 1.5
    public static let embeddingStep: Float = 0.1
    public static let tagWeight: Float = 1.0
    public static let tagStep: Float = 0.15
    public static let decorativeEmbeddingWeight: Float = 4.0
    public static let decorativeMeasureScale: Float = 0.5

    public static let otherClassification: Float = 1
    public static let otherStyleTheme: Float = 2.0
    public static let monospacedOtherSerif: Float = 2.5
    public static let notRounded: Float = 10
    public static let notStencil: Float = 10
    public static let notOutline: Float = 10
    public static let notAllCaps: Float = 4
    public static let sameRootPenalty: Float = 1.0
    static let nearerWeightSteps: Float = 2
    static let monospacedSerifCutoff: Float = 0.025
    static let guardedThemes: Set<String> = [
        "/Theme/Blackletter", "/Theme/Stencil", "/Theme/Art Deco", "/Theme/Pixel",
        "/Theme/Inline", "/Theme/Outline", "/Theme/Brush", "/Theme/Comic", "/Script/Formal",
    ]

    static let slanted: Float = 0.1
    static let roundedWords: Set<String> = ["rounded", "round", "rnd"]
    static let stencilWords: Set<String> = ["stencil"]
    static let outlineWords: Set<String> = ["outline", "inline", "hollow"]
    static let foundryPrefixes: Set<String> = [
        "abc", "gt", "itc", "lt", "mt", "bt", "am", "opr", "hal", "bw", "fs", "ek", "ot", "pf", "ff", "tt", "aa", "aaa", "pt", "st", "dm", "ibm", "sf",
        "adobe", "linotype", "monotype", "berthold", "stempel", "bitstream", "paratype", "urw", "neue", "new", "the",
    ]
    private static let lowercaseMeasures: Set<Int> = [
        LetterMeasurements.Measure.xHeight.rawValue, LetterMeasurements.Measure.ascender.rawValue,
        LetterMeasurements.Measure.descender.rawValue, LetterMeasurements.Measure.doubleStoryA.rawValue,
        LetterMeasurements.Measure.doubleStoryG.rawValue,
    ]

    public enum OpticalSize: Sendable {
        case text
        case display

        public init?(name: String) {
            let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))
            if !words.isDisjoint(with: ["display", "headline", "poster", "deck", "banner", "titling", "fine"]) {
                self = .display
            } else if !words.isDisjoint(with: ["text", "caption", "micro", "agate"]) {
                self = .text
            } else {
                return nil
            }
        }
    }

    static let copyWords: Set<String> = [
        "trial", "unlicensed", "test", "demo", "beta", "variable", "var", "vf", "pro", "std", "plus", "pron", "stdn", "ot",
        "sc", "tc", "hk", "mo", "cyr", "cyrillic", "grk", "greek", "ce", "w1g", "c", "arabic", "hebrew", "armenian", "georgian",
        "thai", "devanagari",
        "lf", "tf", "osf", "scosf", "caps", "smallcaps", "expert", "exp", "alt", "alts", "alternate", "alternates", "swash",
        "swashes", "lig", "ligatures", "fractions", "pi", "ornaments", "initials",
    ]
    static let weightWords: Set<String> = [
        "hairline", "thin", "extralight", "ultralight", "light", "book", "regular", "medium", "semibold", "demibold", "bold",
        "extrabold", "ultrabold", "heavy", "black", "extrablack",
    ]

    static func design(of name: String) -> String {
        var words = StyleName.spaced(name).lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
        if words.count > 1, words[0] == "test" { words.removeFirst() }
        func stripCopies() {
            while words.count > 1, let last = words.last, copyWords.contains(last) || weightWords.contains(last) || isVersion(last) {
                words.removeLast()
                if weightWords.contains(last), words.count > 1, ["semi", "demi", "extra", "ultra"].contains(words.last!) { words.removeLast() }
                if last == "caps", words.count > 1, ["small", "petite", "all"].contains(words.last!) { words.removeLast() }
            }
        }
        stripCopies()
        guard words.count > 1, slopeWords.contains(words.last!) else { return words.joined(separator: " ") }
        let slope = words.removeLast()
        stripCopies()
        return (words + [slope]).joined(separator: " ")
    }

    static let slopeWords: Set<String> = ["italic", "italics", "oblique"]

    static func styleDesign(of name: String) -> String {
        var words = design(of: name).split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, slopeWords.contains(last) || StyleName.widths[last] != nil {
            words.removeLast()
            if words.count > 1, ["extra", "ultra", "semi", "x", "xx"].contains(words.last!) { words.removeLast() }
        }
        return words.joined(separator: " ")
    }

    private static func isVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        guard digits.first?.isWholeNumber == true, digits.allSatisfy({ $0.isWholeNumber || $0 == "." }) else { return false }
        return word.hasPrefix("v") || digits.contains(".") || digits.count >= 4
    }

    public static let longestList = 12

    static func familyRoot(of design: String) -> String {
        var words = design.split(separator: " ").map(String.init)
        while words.count > 1, foundryPrefixes.contains(words[0]) { words.removeFirst() }
        return words.first ?? ""
    }

    public init(families: [Family], measurements: (Family) -> LetterMeasurements?, embeddings: ((Family) -> [Float]?)? = nil,
                styleMeasurements: ((LibraryFace) -> LetterMeasurements?)? = nil, styleEmbeddings: ((LibraryFace) -> [Float]?)? = nil,
                tags: ((Family) -> [Float]?)? = nil, styleTags: ((LibraryFace) -> [Float]?)? = nil, tagNames: [String] = [],
                otherWeights: Bool = false,
                classification: (Family) -> String?,
                decorativeClassifications: Set<String> = [Classification.script.rawValue, Classification.ornamental.rawValue],
                weights: [LetterMeasurements.Measure: Float] = SimilarFonts.weights,
                embeddingWeight: Float = SimilarFonts.embeddingWeight, tagWeight: Float = SimilarFonts.tagWeight,
                otherClassification: Float = SimilarFonts.otherClassification,
                sameRootPenalty: Float = SimilarFonts.sameRootPenalty) {
        let measuring = weights.values.contains { $0 > 0 }, embedding = embeddings != nil && embeddingWeight > 0
        var ids: [String] = [], values: [Float] = [], vectors: [Float] = [], classifications: [String?] = [], sizes: [OpticalSize?] = []
        var rawTags: [[Float]?] = []
        var designs: [String] = [], styleDesigns: [String] = [], italicOnly: [Bool] = [], rounded: [Bool] = []
        var plainDesigns: [String] = [], stencil: [Bool] = [], plainStencilDesigns: [String] = []
        var outline: [Bool] = [], plainOutlineDesigns: [String] = [], allCaps: [Bool] = []
        var decorative: [Bool] = [], roots: [String] = [], regularKinds: [SearchQuery.Style] = [], styleRows: [[SearchQuery.Style: Int]] = []
        var styles: [(family: Int, kind: SearchQuery.Style, values: [Float], embedding: [Float], tags: [Float]?)] = []
        var neighbors: [(family: Int, values: [Float], embedding: [Float], tags: [Float]?)] = []
        func usable(_ measured: LetterMeasurements?, _ embedded: [Float]?) -> Bool {
            Self.usable(measured, embedded, measuring: measuring, embedding: embedding)
        }
        for family in families {
            let measured = measurements(family), embedded = embedding ? embeddings?(family) : nil
            guard usable(measured, embedded) else { continue }
            let regularKind = family.kind(of: family.regular)
            var rows = [regularKind: ids.count]
            for kind in styleMeasurements == nil ? [] : family.kinds where kind != regularKind {
                guard let face = family.representative(of: kind) else { continue }
                if face.id == family.regular.id {
                    rows[kind] = ids.count
                    continue
                }
                let styleMeasured = styleMeasurements?(face), styleEmbedded = embedding ? styleEmbeddings?(face) : nil
                if usable(styleMeasured, styleEmbedded) {
                    styles.append((ids.count, kind, styleMeasured?.values ?? Array(repeating: .nan, count: Self.measures),
                                   styleEmbedded ?? [], styleTags?(face)))
                }
            }
            for face in otherWeights ? family.weightNeighbors : [] {
                let styleMeasured = styleMeasurements?(face), styleEmbedded = embedding ? styleEmbeddings?(face) : nil
                if usable(styleMeasured, styleEmbedded) {
                    neighbors.append((ids.count, styleMeasured?.values ?? Array(repeating: .nan, count: Self.measures),
                                      styleEmbedded ?? [], styleTags?(face)))
                }
            }
            styleRows.append(rows)
            regularKinds.append(regularKind)
            ids.append(family.id)
            values += measured?.values ?? Array(repeating: .nan, count: Self.measures)
            vectors += embedded ?? []
            rawTags.append(tags?(family))
            let familyClass = classification(family)
            classifications.append(familyClass)
            decorative.append(familyClass.map(decorativeClassifications.contains) ?? false)
            sizes.append(OpticalSize(name: family.id))
            let designName = Self.design(of: family.id)
            designs.append(designName)
            roots.append(Self.familyRoot(of: designName))
            styleDesigns.append(Self.styleDesign(of: family.id))
            italicOnly.append(family.regular.face.isItalic)
            let words = family.id.split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
            let plain = words.filter { !Self.roundedWords.contains($0.lowercased()) }
            rounded.append(measured?[.rounded] == 1 || plain.count < words.count)
            plainDesigns.append(Self.design(of: plain.joined(separator: " ")))
            let plainStencil = words.filter { !Self.stencilWords.contains($0.lowercased()) }
            stencil.append(measured?[.stencil] == 1 || plainStencil.count < words.count)
            plainStencilDesigns.append(Self.design(of: plainStencil.joined(separator: " ")))
            let plainOutline = words.filter { !Self.outlineWords.contains($0.lowercased()) }
            outline.append(measured?[.outline] == 1 || plainOutline.count < words.count)
            plainOutlineDesigns.append(Self.design(of: plainOutline.joined(separator: " ")))
            allCaps.append(measured?[.allCaps] == 1)
        }
        for (offset, style) in styles.enumerated() {
            styleRows[style.family][style.kind] = ids.count + offset
            values += style.values
            vectors += style.embedding
            rawTags.append(style.tags)
        }
        var neighborRows = [[Int]](repeating: [], count: ids.count)
        for (offset, neighbor) in neighbors.enumerated() {
            neighborRows[neighbor.family].append(ids.count + styles.count + offset)
            values += neighbor.values
            vectors += neighbor.embedding
            rawTags.append(neighbor.tags)
        }
        let detectedTagCount = rawTags.lazy.compactMap { $0?.count }.first(where: { $0 > 0 }) ?? 0
        var flatTags: [Float] = []
        if detectedTagCount > 0 && tagWeight > 0 {
            flatTags.reserveCapacity(rawTags.count * detectedTagCount)
            for tag in rawTags {
                if let tag, tag.count == detectedTagCount {
                    flatTags += tag
                } else {
                    flatTags += Array(repeating: .nan, count: detectedTagCount)
                }
            }
        }
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        self.values = values
        self.embeddings = vectors
        dimensions = values.isEmpty || vectors.isEmpty ? LetterEmbedding.dimensions : vectors.count / (values.count / Self.measures)
        self.tagVectors = flatTags
        self.tagCount = flatTags.isEmpty ? 0 : detectedTagCount
        self.themeIndices = tagNames.count == self.tagCount
            ? tagNames.enumerated().compactMap { Self.guardedThemes.contains($0.element) ? $0.offset : nil }
            : []
        self.classifications = classifications
        self.sizes = sizes
        self.designs = designs
        self.styleDesigns = styleDesigns
        self.styleRows = styleRows
        self.regularKinds = regularKinds
        self.neighborRows = neighborRows
        self.italicOnly = italicOnly
        self.rounded = rounded
        self.plainDesigns = plainDesigns
        self.stencil = stencil
        self.plainStencilDesigns = plainStencilDesigns
        self.outline = outline
        self.plainOutlineDesigns = plainOutlineDesigns
        self.allCaps = allCaps
        self.decorative = decorative
        self.roots = roots
        scales = LetterMeasurements.Measure.allCases.map { Self.steps[$0] ?? 1 }
        self.weights = LetterMeasurements.Measure.allCases.map { weights[$0] ?? 0 }
        self.embeddingWeight = embedding ? embeddingWeight : 0
        self.tagWeight = self.tagCount > 0 ? tagWeight : 0
        self.otherClassification = otherClassification
        self.sameRootPenalty = sameRootPenalty
        self.decorativeClassifications = decorativeClassifications
    }

    private static func usable(_ measured: LetterMeasurements?, _ embedded: [Float]?, measuring: Bool, embedding: Bool) -> Bool {
        (measured != nil || !measuring) && (embedded != nil || !embedding) && (measured != nil || embedded != nil)
    }

    public static func covers(_ family: Family, kind: SearchQuery.Style? = nil, measurements: (Family) -> LetterMeasurements?,
                              embeddings: ((Family) -> [Float]?)? = nil, styleMeasurements: ((LibraryFace) -> LetterMeasurements?)? = nil,
                              styleEmbeddings: ((LibraryFace) -> [Float]?)? = nil,
                              weights: [LetterMeasurements.Measure: Float] = SimilarFonts.weights,
                              embeddingWeight: Float = SimilarFonts.embeddingWeight) -> Bool {
        let measuring = weights.values.contains { $0 > 0 }, embedding = embeddings != nil && embeddingWeight > 0
        guard usable(measurements(family), embedding ? embeddings?(family) : nil, measuring: measuring, embedding: embedding) else { return false }
        guard let kind, kind != family.kind(of: family.regular) else { return true }
        guard styleMeasurements != nil, family.kinds.contains(kind), let face = family.representative(of: kind) else { return false }
        if face.id == family.regular.id { return true }
        return usable(styleMeasurements?(face), embedding ? styleEmbeddings?(face) : nil, measuring: measuring, embedding: embedding)
    }

    public var count: Int { ids.count }

    public func contains(_ id: String, kind: SearchQuery.Style? = nil) -> Bool {
        guard let reference = positions[id] else { return false }
        return kind.map { styleRows[reference][$0] != nil } ?? true
    }

    public func nearest(to id: String, kind: SearchQuery.Style? = nil, limit: Int) -> [String] {
        nearestWithDistances(to: id, kind: kind, limit: limit).map(\.id)
    }

    public func nearestWithDistances(to id: String, kind: SearchQuery.Style? = nil, limit: Int) -> [(id: String, distance: Float)] {
        guard let reference = positions[id] else { return [] }
        let kind = kind ?? (italicOnly[reference] ? regularKinds[reference] : nil)
        guard let start = kind.map({ styleRows[reference][$0] }) ?? reference else { return [] }
        var found: [(index: Int, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices where other != reference {
            guard let row = kind.map({ self.row(of: other, for: $0) }) ?? other else { continue }
            var apart = distance(reference, start, other, row: row)
            if kind == nil {
                for neighbor in nearerWeights(of: other, than: row, to: start) { apart = min(apart, distance(reference, start, other, row: neighbor)) }
            }
            found.append((other, apart))
        }
        found.sort { $0.distance < $1.distance }
        let keys = kind == nil ? designs : styleDesigns
        let wantedCount = max(limit, Self.longestList)
        var listed: Set = [keys[reference]], nearest: [(index: Int, distance: Float)] = []
        if sameRootPenalty > 0 {
            var pool: [(index: Int, distance: Float)] = []
            var seenPool: Set<String> = [keys[reference]]
            let poolLimit = max(wantedCount * 8, 96)
            for entry in found where seenPool.insert(keys[entry.index]).inserted {
                pool.append(entry)
                if pool.count == poolLimit { break }
            }
            var used = [Bool](repeating: false, count: pool.count)
            var listedRoots: Set<String> = []
            while nearest.count < wantedCount {
                var bestSlot: Int?, bestEffective = Float.infinity
                for (slot, entry) in pool.enumerated() where !used[slot] {
                    let root = roots[entry.index]
                    let effective = entry.distance + (!root.isEmpty && listedRoots.contains(root) ? sameRootPenalty : 0)
                    if effective < bestEffective {
                        bestEffective = effective
                        bestSlot = slot
                    }
                }
                guard let chosen = bestSlot else { break }
                used[chosen] = true
                let entry = pool[chosen]
                if !roots[entry.index].isEmpty { listedRoots.insert(roots[entry.index]) }
                nearest.append(entry)
            }
        } else {
            for entry in found where listed.insert(keys[entry.index]).inserted {
                nearest.append(entry)
                if nearest.count == wantedCount { break }
            }
        }
        if let own = sizes[reference] {
            let slots = nearest.indices.filter { sizes[nearest[$0].index] != nil }
            let named = slots.map { nearest[$0] }
            let ordered = named.filter { sizes[$0.index] == own } + named.filter { sizes[$0.index] != own }
            for (slot, entry) in zip(slots, ordered) { nearest[slot] = entry }
        }
        return nearest.prefix(limit).map { (ids[$0.index], $0.distance) }
    }

    public func nearest(measurements: LetterMeasurements?, embedding: [Float]?, tags: [Float]? = nil,
                        classification: String? = nil, name: String? = nil, limit: Int) -> [String] {
        guard measurements != nil || (embedding != nil && embeddingWeight > 0) else { return [] }
        let queryValues = measurements?.values ?? Array(repeating: .nan, count: Self.measures)
        let queryEmbedding = embedding?.count == dimensions ? embedding : nil
        let queryTags = tags?.count == tagCount ? tags : nil
        let isDecorative = classification.map(decorativeClassifications.contains) ?? false
        let isAllCaps = queryValues[LetterMeasurements.Measure.allCaps.rawValue] == 1
        let words = (name ?? "").split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
        let plainRounded = Self.design(of: words.filter { !Self.roundedWords.contains($0.lowercased()) }.joined(separator: " "))
        let isRounded = queryValues[LetterMeasurements.Measure.rounded.rawValue] == 1 || words.contains { Self.roundedWords.contains($0.lowercased()) }
        let plainStencil = Self.design(of: words.filter { !Self.stencilWords.contains($0.lowercased()) }.joined(separator: " "))
        let isStencil = queryValues[LetterMeasurements.Measure.stencil.rawValue] == 1 || words.contains { Self.stencilWords.contains($0.lowercased()) }
        let plainOutline = Self.design(of: words.filter { !Self.outlineWords.contains($0.lowercased()) }.joined(separator: " "))
        let isOutline = queryValues[LetterMeasurements.Measure.outline.rawValue] == 1 || words.contains { Self.outlineWords.contains($0.lowercased()) }
        let querySize = name.flatMap(OpticalSize.init(name:))
        var found: [(index: Int, distance: Float)] = []
        found.reserveCapacity(ids.count)
        for other in ids.indices {
            let apart = externalDistance(
                queryValues: queryValues, queryEmbedding: queryEmbedding, queryTags: queryTags,
                queryClassification: classification, isDecorative: isDecorative, isAllCaps: isAllCaps,
                isRounded: isRounded, plainRounded: plainRounded, isStencil: isStencil, plainStencil: plainStencil,
                isOutline: isOutline, plainOutline: plainOutline, to: other
            )
            found.append((other, apart))
        }
        found.sort { $0.distance < $1.distance }
        let wantedCount = max(limit, Self.longestList)
        var nearest: [(index: Int, distance: Float)] = []
        if sameRootPenalty > 0 {
            var pool: [(index: Int, distance: Float)] = []
            var seenPool: Set<String> = []
            let poolLimit = max(wantedCount * 8, 96)
            for entry in found where seenPool.insert(designs[entry.index]).inserted {
                pool.append(entry)
                if pool.count == poolLimit { break }
            }
            var used = [Bool](repeating: false, count: pool.count)
            var listedRoots: Set<String> = []
            while nearest.count < wantedCount {
                var bestSlot: Int?, bestEffective = Float.infinity
                for (slot, entry) in pool.enumerated() where !used[slot] {
                    let root = roots[entry.index]
                    let effective = entry.distance + (!root.isEmpty && listedRoots.contains(root) ? sameRootPenalty : 0)
                    if effective < bestEffective {
                        bestEffective = effective
                        bestSlot = slot
                    }
                }
                guard let chosen = bestSlot else { break }
                used[chosen] = true
                let entry = pool[chosen]
                if !roots[entry.index].isEmpty { listedRoots.insert(roots[entry.index]) }
                nearest.append(entry)
            }
        } else {
            var listed: Set<String> = []
            for entry in found where listed.insert(designs[entry.index]).inserted {
                nearest.append(entry)
                if nearest.count == wantedCount { break }
            }
        }
        if let own = querySize {
            let slots = nearest.indices.filter { sizes[nearest[$0].index] != nil }
            let named = slots.map { nearest[$0] }
            let ordered = named.filter { sizes[$0.index] == own } + named.filter { sizes[$0.index] != own }
            for (slot, entry) in zip(slots, ordered) { nearest[slot] = entry }
        }
        return nearest.prefix(limit).map { ids[$0.index] }
    }

    private func nearerWeights(of family: Int, than row: Int, to start: Int) -> [Int] {
        let weight = LetterMeasurements.Measure.weight.rawValue
        let wanted = values[start * Self.measures + weight], own = values[row * Self.measures + weight]
        guard !wanted.isNaN, !neighborRows[family].isEmpty else { return [] }
        let limit = Self.nearerWeightSteps * (Self.steps[.weight] ?? 1)
        return neighborRows[family].filter { neighbor in
            let other = values[neighbor * Self.measures + weight]
            return !other.isNaN && abs(other - wanted) <= limit && (own.isNaN || abs(other - wanted) < abs(own - wanted))
        }
    }

    private func row(of family: Int, for kind: SearchQuery.Style) -> Int? {
        if let row = styleRows[family][kind] { return row }
        let near = styleRows[family].filter { $0.key.isItalic == kind.isItalic && $0.key.side == kind.side }
            .min { abs(($0.key.width ?? 5) - (kind.width ?? 5)) < abs(($1.key.width ?? 5) - (kind.width ?? 5)) }
        if let near { return near.value }
        let slant = values[family * Self.measures + LetterMeasurements.Measure.slant.rawValue]
        return kind.isItalic && !regularKinds[family].isItalic && regularKinds[family].side == kind.side && abs(slant) > Self.slanted ? family : nil
    }

    static let oneMissing: Float = 1.5

    private func distance(_ a: Int, _ start: Int, _ b: Int, row: Int) -> Float {
        var sum: Float = 0
        let base = start * Self.measures, other = row * Self.measures
        let isDecorative = decorative[a], isAllCaps = allCaps[a]
        let measureScale: Float = isDecorative ? Self.decorativeMeasureScale : 1
        for measure in 0..<Self.measures where weights[measure] > 0 {
            if isAllCaps && Self.lowercaseMeasures.contains(measure) { continue }
            let x = values[base + measure], y = values[other + measure]
            let steps: Float = switch (x.isNaN, y.isNaN) {
            case (false, false): min(abs(x - y) / scales[measure], 4)
            case (true, true): 0
            default: Self.oneMissing
            }
            sum += weights[measure] * measureScale * steps * steps
        }
        if embeddingWeight > 0 {
            let activeEmbeddingWeight = isDecorative ? max(embeddingWeight, Self.decorativeEmbeddingWeight) : embeddingWeight
            var squares: Float = 0
            for index in 0..<dimensions {
                let difference = embeddings[start * dimensions + index] - embeddings[row * dimensions + index]
                squares += difference * difference
            }
            sum += activeEmbeddingWeight * squares / (Self.embeddingStep * Self.embeddingStep)
        }
        var themePenalty: Float = 0
        if tagWeight > 0 {
            let firstBase = start * tagCount, secondBase = row * tagCount
            if !tagVectors[firstBase].isNaN && !tagVectors[secondBase].isNaN {
                var squares: Float = 0, normA: Float = 0, normB: Float = 0
                for index in 0..<tagCount {
                    let x = tagVectors[firstBase + index], y = tagVectors[secondBase + index]
                    normA += x * x
                    normB += y * y
                }
                if normA > 1e-6 && normB > 1e-6 {
                    let invA = 1 / normA.squareRoot(), invB = 1 / normB.squareRoot()
                    for index in 0..<tagCount {
                        let difference = tagVectors[firstBase + index] * invA - tagVectors[secondBase + index] * invB
                        squares += difference * difference
                    }
                    sum += tagWeight * squares / (Self.tagStep * Self.tagStep)
                }
                for index in themeIndices {
                    if tagVectors[firstBase + index] >= 0.65 && tagVectors[secondBase + index] < 0.25 {
                        themePenalty = Self.otherStyleTheme
                        break
                    }
                }
            }
        }
        var apart = sum.squareRoot() + themePenalty
        if let first = classifications[a], let second = classifications[b], first != second { apart += otherClassification }
        let monoIndex = LetterMeasurements.Measure.monospaced.rawValue, serifIndex = LetterMeasurements.Measure.serifLength.rawValue
        if values[base + monoIndex] == 1 && values[other + monoIndex] == 1 {
            let firstSerif = values[base + serifIndex], secondSerif = values[other + serifIndex]
            if !firstSerif.isNaN && !secondSerif.isNaN && (firstSerif >= Self.monospacedSerifCutoff) != (secondSerif >= Self.monospacedSerifCutoff) {
                apart += Self.monospacedOtherSerif
            }
        }
        if rounded[a], !rounded[b], designs[b] != plainDesigns[a] { apart += Self.notRounded }
        if stencil[a], !stencil[b], designs[b] != plainStencilDesigns[a] { apart += Self.notStencil }
        if outline[a], !outline[b], designs[b] != plainOutlineDesigns[a] { apart += Self.notOutline }
        if isAllCaps, !allCaps[b], designs[b] != designs[a] { apart += Self.notAllCaps }
        return apart
    }

    private func externalDistance(queryValues: [Float], queryEmbedding: [Float]?, queryTags: [Float]?, queryClassification: String?,
                                  isDecorative: Bool, isAllCaps: Bool, isRounded: Bool, plainRounded: String, isStencil: Bool,
                                  plainStencil: String, isOutline: Bool, plainOutline: String, to b: Int) -> Float {
        var sum: Float = 0
        let other = b * Self.measures
        let measureScale: Float = isDecorative ? Self.decorativeMeasureScale : 1
        let hasMeasures = queryValues.contains { !$0.isNaN }
        if hasMeasures {
            for measure in 0..<Self.measures where weights[measure] > 0 {
                if isAllCaps && Self.lowercaseMeasures.contains(measure) { continue }
                let x = queryValues[measure], y = values[other + measure]
                let steps: Float = switch (x.isNaN, y.isNaN) {
                case (false, false): min(abs(x - y) / scales[measure], 4)
                case (true, true): 0
                default: Self.oneMissing
                }
                sum += weights[measure] * measureScale * steps * steps
            }
        }
        if let queryEmbedding, embeddingWeight > 0 {
            let activeEmbeddingWeight = isDecorative || !hasMeasures ? max(embeddingWeight, Self.decorativeEmbeddingWeight) : embeddingWeight
            var squares: Float = 0
            for index in 0..<dimensions {
                let difference = queryEmbedding[index] - embeddings[b * dimensions + index]
                squares += difference * difference
            }
            sum += activeEmbeddingWeight * squares / (Self.embeddingStep * Self.embeddingStep)
        }
        var themePenalty: Float = 0
        if let queryTags, tagWeight > 0 {
            let secondBase = b * tagCount
            if !tagVectors[secondBase].isNaN {
                var squares: Float = 0, normA: Float = 0, normB: Float = 0
                for index in 0..<tagCount {
                    let x = queryTags[index], y = tagVectors[secondBase + index]
                    normA += x * x
                    normB += y * y
                }
                if normA > 1e-6 && normB > 1e-6 {
                    let invA = 1 / normA.squareRoot(), invB = 1 / normB.squareRoot()
                    for index in 0..<tagCount {
                        let difference = queryTags[index] * invA - tagVectors[secondBase + index] * invB
                        squares += difference * difference
                    }
                    sum += tagWeight * squares / (Self.tagStep * Self.tagStep)
                }
                for index in themeIndices {
                    if queryTags[index] >= 0.65 && tagVectors[secondBase + index] < 0.25 {
                        themePenalty = Self.otherStyleTheme
                        break
                    }
                }
            }
        }
        var apart = sum.squareRoot() + themePenalty
        if let first = queryClassification, let second = classifications[b], first != second { apart += otherClassification }
        let monoIndex = LetterMeasurements.Measure.monospaced.rawValue, serifIndex = LetterMeasurements.Measure.serifLength.rawValue
        if queryValues[monoIndex] == 1 && values[other + monoIndex] == 1 {
            let firstSerif = queryValues[serifIndex], secondSerif = values[other + serifIndex]
            if !firstSerif.isNaN && !secondSerif.isNaN && (firstSerif >= Self.monospacedSerifCutoff) != (secondSerif >= Self.monospacedSerifCutoff) {
                apart += Self.monospacedOtherSerif
            }
        }
        if isRounded, !rounded[b], designs[b] != plainRounded { apart += Self.notRounded }
        if isStencil, !stencil[b], designs[b] != plainStencil { apart += Self.notStencil }
        if isOutline, !outline[b], designs[b] != plainOutline { apart += Self.notOutline }
        if isAllCaps, !allCaps[b] { apart += Self.notAllCaps }
        return apart
    }
}
