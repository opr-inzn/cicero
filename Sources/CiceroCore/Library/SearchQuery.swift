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
}
