import Foundation

/// What's typed in the search field. A family matches when the query's words can be split into runs that each begin
/// one of its terms, the words for what kind of family it is (variable, monospaced, its classification, display or
/// text, condensed, its tags), or begin a word in one of its texts (its names and its styles', its foundry, a style's
/// PostScript name, designer or vendor ID, its note). So the whole query at the start of a word in a name finds a
/// family, but "mono" also finds every monospaced one, "variable sans" variable sans serifs, and "inter variable" Inter
/// if it's variable. A term only begins with a run, so "serif" doesn't find sans serifs by their classification, and
/// a run only begins a word, so "am" finds American Typewriter but not every family from a foundry with "am" inside
/// its name. Typing more of a word only ever narrows what's found, unless it stops being a keyword ("mono", then
/// "monot"). Where nothing has a word that begins with it, `anywhereInNames` looks inside words of names too.
///
/// A run that's a keyword, one of the words for a kind of family, is looked for in the family's and its styles' names
/// and its note only, not in the rest of its texts: "mono" finds monospaced families and families with Mono in a name,
/// but not every font from Monotype.
public struct SearchQuery: Sendable {
    /// Lowercased, with one space between its words.
    public let text: String
    /// Whether a run is found inside a word of a name too, not only where one begins.
    public private(set) var isAnywhereInNames = false
    /// Every run of consecutive words, by first word and length less one: runs[1][0] is the second word, runs[0][1]
    /// the first two.
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

    /// The same query, finding its runs inside words of names too, like "vetica" in Helvetica: for when nothing has a
    /// word that begins with them.
    public var anywhereInNames: SearchQuery {
        var query = self
        query.isAnywhereInNames = true
        return query
    }

    /// Whether the query matches a family with these names (its own and its styles', and its note), other texts and
    /// terms, lowercased.
    public func matches(names: [String], texts: [String], terms: [String]) -> Bool {
        guard !isEmpty else { return true }
        func found(_ run: Run) -> Bool {
            terms.contains { $0.hasPrefix(run.text) }
                || names.contains { isAnywhereInNames ? $0.contains(run.text) : Self.beginsWord(run.text, in: $0) }
                || !run.isKeyword && texts.contains { Self.beginsWord(run.text, in: $0) }
        }
        // covered[i]: the words before the i-th split into runs that are found.
        var covered = [true] + Array(repeating: false, count: runs.count)
        for start in runs.indices where covered[start] {
            for (length, run) in runs[start].enumerated() where !covered[start + length + 1] && found(run) {
                covered[start + length + 1] = true
            }
            if covered[runs.count] { return true }
        }
        return false
    }

    /// How well a family's name, lowercased, suits the query as a suggestion in the search field: 0 when the name
    /// begins with the whole query, 1 when a later word in it does, nil when none does.
    public func suggestionRank(of name: String) -> Int? {
        guard !isEmpty else { return nil }
        if name.hasPrefix(text) { return 0 }
        return Self.beginsWord(text, in: name) ? 1 : nil
    }

    /// Whether `run` is in `text` where a word begins: at its start, or after a character that's neither a letter nor
    /// a digit. A run that doesn't begin with a letter or digit itself, like "-bold", can be anywhere.
    static func beginsWord(_ run: String, in text: String) -> Bool {
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

    // MARK: Words for kinds of family

    static let narrow = ["condensed", "compressed", "narrow"]
    static let wide = ["extended", "expanded", "wide"]
    static let slab = ["slab serif", "slab"]
    static let opticalSize = ["optical size", "opsz"]

    /// Every word for a kind of family, in any family's terms.
    static let keywords: Set<String> = Set(
        Classification.allCases.flatMap(\.searchTerms) + narrow + wide + slab + opticalSize + FontFileReader.fontExtensions
            + ["variable", "italics", "italic", "text", "display"]
    )

    // MARK: Styles a search names

    /// A style the query names by words for a slope, a width or a weight, for previews to show that style of the families
    /// it finds rather than their regular: "italic" their italics, "condensed" their condensed styles, "bold italic" their
    /// bold italics (see `Family.previewStyle(for:weight:)`).
    public struct Style: Equatable, Sendable {
        public var isItalic = false
        /// On the OS/2 scale, 1 (ultra-condensed) … 5 (normal) … 9 (ultra-expanded).
        public var width: Int?
        /// On the OS/2 scale, as a style's name spells it out (see `StyleName`).
        public var weight: Int?
    }

    /// The style the query names for a family's previews; nil when it names none. Only words spelled out count ("italic",
    /// not "it"), and not those that begin a word in one of the family's names, lowercased: those name the family, as
    /// "condensed" does Avenir Next Condensed, which then shows as usual.
    public func style(forFamilyNamed names: [String]) -> Style? {
        let words = text.split(separator: " ").filter { word in !names.contains { Self.beginsWord(String(word), in: $0) } }
        var style = Style()
        // Joined as in style names, so "semi bold" is semibold.
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
    /// Of `StyleName`'s widths, those spelled out.
    static let widthWords: Set<String> = [
        "ultracondensed", "ultracompressed", "extracondensed", "extracompressed", "compressed", "condensed", "narrow",
        "semicondensed", "semicompressed", "semiextended", "semiexpanded", "semiwide", "extended", "expanded", "wide",
        "extraextended", "extraexpanded", "extrawide", "ultraextended", "ultraexpanded", "ultrawide",
    ]
    /// Of `StyleName`'s weights, those spelled out, but for words more often in a name than for a weight ("roman",
    /// "super", "ultra").
    static let weightWords: Set<String> = [
        "hairline", "thin", "extrathin", "ultrathin", "extralight", "ultralight", "light", "semilight", "book", "regular",
        "medium", "semibold", "demibold", "bold", "extrabold", "ultrabold", "heavy", "black", "extrablack", "ultrablack",
    ]
}

extension Classification {
    /// The words a search finds families of the classification by, besides the name the user gave it: its own and the
    /// usual ones for it, like Google Fonts' and CSS's ("sans-serif", "handwriting", "display").
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
    /// The words a search finds the family by for what kind of family its fonts say it is (see `SearchQuery`), but for
    /// its classification, which the app can put it in another of: variable, monospaced, with italics, with an optical
    /// size axis, for text or display sizes as that axis or its name says (see `SimilarFonts.OpticalSize`), with styles
    /// narrower or wider than normal, a slab serif as its OS/2 family class says, the kinds of file it comes in; and
    /// for a monospaced family, what that class says its letters are, so "sans mono" finds a monospaced sans serif.
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
        // On a width axis, against the regular's place on it, as not every font's is in percent (Skia's goes from 0.62
        // to 1.3); else by the OS/2 width class.
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

    /// The style to preview the family in for a search, and the weight to draw it at: the one its tokens and typed words
    /// name (see `SearchToken.style(of:over:)` and `SearchQuery.Style`), else the one for `weight`, at that weight. A
    /// weight they name is where a variable style of that weight sits on the weight axis, as not every font's axis is on
    /// the OS/2 scale (one has its Light at 450), else that weight.
    public func previewStyle(for query: SearchQuery, tokens: [SearchToken] = [], weight: Double) -> (face: LibraryFace, weight: Double) {
        let typed = query.isEmpty ? nil : query.style(forFamilyNamed: [id.lowercased(), name.lowercased()])
        guard let style = SearchToken.style(of: tokens, over: typed) else { return (face(nearestWeight: weight), weight) }
        guard let named = style.weight else { return (face(for: style, weight: weight), weight) }
        let face = face(for: style, weight: Double(named))
        let isNamed = face.face.weightAxis != nil && FontFace.hundreds(face.face.namedWeight) == FontFace.hundreds(Double(named))
        return (face, isNamed ? face.face.styleWeight : Double(named))
    }

    /// The style nearest one a search names: of the italics when it's italic, else of the uprights; of those, the ones
    /// nearest its width, on the narrower or wider side when there are any; then the one nearest the weight, by its name
    /// when that says one (a Bold the file classes at 400 is still Bold), the normal width first among the same weight. A
    /// variable style with a weight axis comes first, as it draws every weight, and of the variable styles, with a weight
    /// axis or not, the ones where the regular is on the axes the search says nothing about. Not one of ornaments, unless
    /// that's all there is. When the family has none of a kind, the next step chooses among them all, so a family without
    /// italics shows its upright.
    func face(for style: SearchQuery.Style, weight: Double) -> LibraryFace {
        let letters = faces.filter { !$0.face.isOrnaments }
        var candidates = letters.isEmpty ? faces : letters
        func keep(_ test: (LibraryFace) -> Bool) {
            let kept = candidates.filter(test)
            if !kept.isEmpty { candidates = kept }
        }
        keep { $0.face.isItalic == style.isItalic }
        if let wanted = style.width {
            keep { (widthClass(of: $0.face) - 5).signum() == (wanted - 5).signum() }
            let nearest = candidates.map { abs(widthClass(of: $0.face) - wanted) }.min()
            keep { abs(widthClass(of: $0.face) - wanted) == nearest }
        }
        keep { $0.face.weightAxis != nil }
        // A static style has no axes to be moved on, so it stays beside them.
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

    /// How wide a style is on the OS/2 scale, 1 (ultra-condensed) … 5 (normal) … 9 (ultra-expanded): as its name spells
    /// it out, else on a width axis against the regular's place on it, as not every font's is in percent (narrower is 3,
    /// wider 7), else by its OS/2 width class.
    func widthClass(of face: FontFace) -> Int {
        if let named = StyleName(face.styleName).width { return named }
        if let value = face.axes.first(where: { $0.tag == "wdth" })?.value {
            let normal = regular.face.axes.first { $0.tag == "wdth" }?.value ?? 100
            return value < normal ? 3 : value > normal ? 7 : 5
        }
        return face.width
    }
}

extension FontFace {
    /// Its weight as its name spells it out, as a Bold the file classes at 400 is still Bold; the regular weight for a
    /// name of only widths and slopes ("Italic", "Condensed"); else its place on the weight axis or its OS/2 class.
    var namedWeight: Double {
        let name = StyleName(styleName)
        return name.weight.map(Double.init) ?? (name.isRegular ? 400 : styleWeight)
    }

    /// A weight to the nearest hundred, from 100 to 900: Book (350) is a Regular, Heavy (850) a Black.
    static func hundreds(_ weight: Double) -> Int {
        min(max(Int((weight / 100).rounded()) * 100, 100), 900)
    }
}
