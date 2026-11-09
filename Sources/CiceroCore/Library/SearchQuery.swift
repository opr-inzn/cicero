import Foundation

public struct SearchQuery: Sendable {
    public let text: String
    public private(set) var isAnywhereInNames = false
    private let runs: [[Run]]

    private struct Run: Sendable {
        var text: String
        var isKeyword: Bool
    }

    public init(_ typed: String) {
        let words = typed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        text = words.joined(separator: " ")
        runs = words.indices.map { start in
            (start..<words.count).map { end in
                let run = words[start...end].joined(separator: " ")
                return Run(text: run, isKeyword: Self.keywords.contains(run))
            }
        }
    }

    public var isEmpty: Bool { text.isEmpty }

    public var anywhereInNames: SearchQuery {
        var query = self
        query.isAnywhereInNames = true
        return query
    }

    public func matches(names: [String], texts: [String], terms: [String]) -> Bool {
        guard !isEmpty else { return true }
        func found(_ run: Run) -> Bool {
            terms.contains { $0.hasPrefix(run.text) }
                || names.contains { isAnywhereInNames ? Self.contains(run.text, in: $0) : Self.beginsWord(run.text, in: $0) }
                || !run.isKeyword && texts.contains { Self.beginsWord(run.text, in: $0) }
        }
        var covered = [true] + Array(repeating: false, count: runs.count)
        for start in runs.indices where covered[start] {
            for (length, run) in runs[start].enumerated() where !covered[start + length + 1] && found(run) {
                covered[start + length + 1] = true
            }
            if covered[runs.count] { return true }
        }
        return false
    }

    public func suggestionRank(of name: String) -> Int? {
        guard !isEmpty else { return nil }
        if name.hasPrefix(text) { return 0 }
        return Self.beginsWord(text, in: name) ? 1 : nil
    }

    static func beginsWord(_ run: String, in text: String) -> Bool {
        if let found = asciiFind(run, in: text, wordStart: true) { return found }
        guard let first = run.first, first.isLetter || first.isNumber else { return text.contains(run) }
        var rest = text[...]
        while let range = rest.range(of: run) {
            if range.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: range.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            rest = text[text.index(after: range.lowerBound)...]
        }
        return false
    }

    static func contains(_ run: String, in text: String) -> Bool {
        asciiFind(run, in: text, wordStart: false) ?? text.contains(run)
    }

    private static func asciiFind(_ run: String, in text: String, wordStart: Bool) -> Bool? {
        var run = run, text = text
        return run.withUTF8 { run in
            text.withUTF8 { text -> Bool? in
                // ASCII only: a byte over 127 could be part of a character the run's last letter only begins, like an e with a combining accent.
                guard let first = run.first, !run.contains(where: { $0 > 127 }), !text.contains(where: { $0 > 127 }) else { return nil }
                guard run.count <= text.count else { return false }
                let atWordStart = wordStart && isASCIILetterOrDigit(first)
                for start in 0...(text.count - run.count) where text[start] == first {
                    if atWordStart, start > 0, isASCIILetterOrDigit(text[start - 1]) { continue }
                    if memcmp(run.baseAddress! + 1, text.baseAddress! + start + 1, run.count - 1) == 0 { return true }
                }
                return false
            }
        }
    }

    private static func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
        let lower = byte | 0x20
        return (0x30...0x39).contains(byte) || (0x61...0x7A).contains(lower)
    }

    // MARK: Words for kinds of family

    static let narrow = ["condensed", "compressed", "narrow"]
    static let wide = ["extended", "expanded", "wide"]
    static let slab = ["slab serif", "slab"]
    static let opticalSize = ["optical size", "opsz"]

    static let keywords: Set<String> = Set(
        Classification.allCases.flatMap(\.searchTerms) + narrow + wide + slab + opticalSize + FontFileReader.fontExtensions
            + ["variable", "italics", "italic", "text", "display"]
    )

    // MARK: Styles a search names

    public struct Style: Hashable, Sendable {
        public var isItalic = false
        public var width: Int?
        public var weight: Int?

        public init(isItalic: Bool = false, width: Int? = nil, weight: Int? = nil) {
            self.isItalic = isItalic
            self.width = width
            self.weight = weight
        }

        var side: Int { ((width ?? 5) - 5).signum() }
    }

    public func style(forFamilyNamed names: [String]) -> Style? {
        let words = text.split(separator: " ").filter { word in !names.contains { Self.beginsWord(String(word), in: $0) } }
        var style = Style()
        for word in StyleName.words(words.joined(separator: " ")) {
            if Self.slopeWords.contains(word) {
                style.isItalic = true
            } else if Self.widthWords.contains(word) {
                style.width = style.width ?? StyleName.widths[word]
            } else if Self.weightWords.contains(word) {
                style.weight = style.weight ?? StyleName.weights[word]
            }
        }
        return style == Style() ? nil : style
    }

    static let slopeWords: Set<String> = ["italic", "italics", "oblique"]
    static let widthWords: Set<String> = [
        "ultracondensed", "ultracompressed", "extracondensed", "extracompressed", "compressed", "condensed", "narrow",
        "semicondensed", "semicompressed", "semiextended", "semiexpanded", "semiwide", "extended", "expanded", "wide",
        "extraextended", "extraexpanded", "extrawide", "ultraextended", "ultraexpanded", "ultrawide",
    ]
    // Not "roman", "super" or "ultra", more often in a name than for a weight.
    static let weightWords: Set<String> = [
        "hairline", "thin", "extrathin", "ultrathin", "extralight", "ultralight", "light", "semilight", "book", "regular",
        "medium", "semibold", "demibold", "bold", "extrabold", "ultrabold", "heavy", "black", "extrablack", "ultrablack",
    ]
}

extension Classification {
    public var searchTerms: [String] {
        switch self {
        case .serif: ["serif"]
        case .sansSerif: ["sans serif", "sans-serif", "sans"]
        case .monospaced: ["monospaced", "mono"]
        case .script: ["script", "handwriting", "cursive"]
        case .ornamental: ["ornamental", "decorative", "display"]
        case .symbol: ["symbol", "dingbats"]
        case .unclassified: ["unclassified"]
        }
    }
}

extension Family {
    var searchTerms: [String] {
        let faces = faces.map(\.face)
        var terms: [String] = []
        if isVariable { terms.append("variable") }
        if isMonospaced { terms += ["monospaced", "mono"] }
        if hasItalics { terms += ["italics", "italic"] }
        let hasOpticalSize = faces.contains { $0.axes.contains { $0.tag == "opsz" } }
        if hasOpticalSize { terms += SearchQuery.opticalSize }
        let size = SimilarFonts.OpticalSize(name: id)
        if hasOpticalSize || size == .text { terms.append("text") }
        if hasOpticalSize || size == .display { terms.append("display") }
        // On a width axis, against the regular's place on it, as not every font's is in percent (Skia's goes from 0.62 to 1.3); else by the OS/2 width class.
        let normal = regular.face.axes.first { $0.tag == "wdth" }?.value ?? 100
        let widths = faces.map { face in
            face.axes.first { $0.tag == "wdth" }.map { $0.value < normal ? -1 : $0.value > normal ? 1 : 0 } ?? (face.width - 5).signum()
        }
        if widths.contains(-1) { terms += SearchQuery.narrow }
        if widths.contains(1) { terms += SearchQuery.wide }
        let upright = Classification.judged(self.faces)[0]
        if upright.familyClass == 5 { terms += SearchQuery.slab }
        if let byClass = Classification(familyClass: upright.familyClass), byClass != classification { terms += byClass.searchTerms }
        terms += Set(faces.map { ($0.path as NSString).pathExtension.lowercased() }).sorted()
        return terms
    }

    public func namesStyle(_ query: SearchQuery, tokens: [SearchToken]) -> Bool {
        let typed = query.isEmpty ? nil : query.style(forFamilyNamed: [id.lowercased(), name.lowercased()])
        return SearchToken.style(of: tokens, over: typed) != nil
    }

    public func previewStyle(for query: SearchQuery, tokens: [SearchToken] = [], weight: Double) -> (face: LibraryFace, weight: Double) {
        let typed = query.isEmpty ? nil : query.style(forFamilyNamed: [id.lowercased(), name.lowercased()])
        let variable = tokens.contains(.variable)
        guard let style = SearchToken.style(of: tokens, over: typed) else {
            let nearest = face(nearestWeight: weight)
            return (variable && nearest.face.axes.isEmpty ? face(for: SearchQuery.Style(), weight: weight, variable: true) : nearest, weight)
        }
        guard let named = style.weight else { return (face(for: style, weight: weight, variable: variable), weight) }
        let face = face(for: style, weight: Double(named), variable: variable)
        // Where a variable style of the named weight sits on its axis, as not every font's weight axis is on the OS/2 scale (one has its Light at 450).
        let isNamed = face.face.weightAxis != nil && FontFace.hundreds(face.face.namedWeight) == FontFace.hundreds(Double(named))
        return (face, isNamed ? face.face.styleWeight : Double(named))
    }

    public func kind(of face: LibraryFace) -> SearchQuery.Style {
        let width = widthClass(of: face.face)
        return SearchQuery.Style(isItalic: face.face.isItalic, width: width == 5 ? nil : width)
    }

    public var kinds: [SearchQuery.Style] {
        let letters = faces.filter { !$0.face.isOrnaments }
        var kinds: [SearchQuery.Style] = []
        for face in letters.isEmpty ? faces : letters {
            let kind = kind(of: face)
            if !kinds.contains(kind) { kinds.append(kind) }
        }
        return kinds
    }

    public func representative(of kind: SearchQuery.Style) -> LibraryFace? {
        let face = face(for: SearchQuery.Style(isItalic: kind.isItalic, width: kind.width), weight: 400)
        let found = self.kind(of: face)
        return found.isItalic == kind.isItalic && found.side == kind.side ? face : nil
    }

    public func face(for style: SearchQuery.Style, weight: Double, variable: Bool = false) -> LibraryFace {
        let letters = faces.filter { !$0.face.isOrnaments }
        var candidates = letters.isEmpty ? faces : letters
        func keep(_ test: (LibraryFace) -> Bool) {
            let kept = candidates.filter(test)
            if !kept.isEmpty { candidates = kept }
        }
        if variable { keep { !$0.face.axes.isEmpty } }
        keep { $0.face.isItalic == style.isItalic }
        if let wanted = style.width {
            keep { (widthClass(of: $0.face) - 5).signum() == (wanted - 5).signum() }
            let nearest = candidates.map { abs(widthClass(of: $0.face) - wanted) }.min()
            keep { abs(widthClass(of: $0.face) - wanted) == nearest }
        }
        keep { $0.face.weightAxis != nil }
        let named = ["wght"] + (style.isItalic ? ["ital", "slnt"] : []) + (style.width == nil ? [] : ["wdth"])
        let origin = Dictionary(regular.face.axes.map { ($0.tag, $0.value) }) { first, _ in first }
        func moved(_ face: FontFace) -> Int {
            face.axes.count { axis in !named.contains(axis.tag) && origin[axis.tag].map { abs($0 - axis.value) > 0.01 } == true }
        }
        let least = candidates.map { moved($0.face) }.min()
        keep { moved($0.face) == least }
        return candidates.min { a, b in
            let (first, second) = (abs(a.face.namedWeight - weight), abs(b.face.namedWeight - weight))
            return first != second ? first < second : abs(widthClass(of: a.face) - 5) < abs(widthClass(of: b.face) - 5)
        }!
    }

    func widthClass(of face: FontFace) -> Int {
        if let named = StyleName(face.styleName).width { return named }
        if let value = face.axes.first(where: { $0.tag == "wdth" })?.value {
            // Against the regular's place on the axis, as not every font's width axis is in percent.
            let normal = regular.face.axes.first { $0.tag == "wdth" }?.value ?? 100
            return value < normal ? 3 : value > normal ? 7 : 5
        }
        return face.width
    }
}

extension FontFace {
    var namedWeight: Double {
        // By its name first: a Bold its file classes at 400 is still Bold.
        let name = StyleName(styleName)
        return name.weight.map(Double.init) ?? (name.isRegular ? 400 : styleWeight)
    }

    static func hundreds(_ weight: Double) -> Int {
        min(max(Int((weight / 100).rounded()) * 100, 100), 900)
    }
}
