import CoreText
import Foundation

/// A filter in the search field beside what's typed, chosen from its suggestions: a style the families have to have,
/// which their previews then show (see `Family.previewStyle(for:tokens:weight:)`), figures they have to be able to
/// set, which their previews then use, or variable styles. A family has to match every token, and the text.
public enum SearchToken: Hashable, Identifiable, Sendable {
    case italic
    /// On the OS/2 scale, a multiple of 100 from 100 to 900.
    case weight(Int)
    case condensed
    case extended
    case tabularFigures
    case oldStyleFigures
    case variable

    public var id: Self { self }

    /// Every token, in the order the suggestions list them.
    public static let all: [SearchToken] = [.italic] + weights.map { .weight($0.weight) } + [.condensed, .extended, .tabularFigures, .oldStyleFigures, .variable]

    /// The weights' names, and the other words for them.
    private static let weights: [(weight: Int, name: String, others: [String])] = [
        (100, "Thin", ["hairline"]), (200, "Extra Light", ["extralight", "ultra light", "ultralight"]), (300, "Light", []),
        (400, "Regular", []), (500, "Medium", []), (600, "Semibold", ["semi bold", "demibold", "demi bold"]), (700, "Bold", []),
        (800, "Extra Bold", ["extrabold", "ultra bold", "ultrabold"]), (900, "Black", ["heavy"]),
    ]

    public var title: String {
        switch self {
        case .italic: "Italic"
        case .weight(let weight): Self.weights.first { $0.weight == weight }?.name ?? String(weight)
        case .condensed: "Condensed"
        case .extended: "Extended"
        case .tabularFigures: "Tabular Figures"
        case .oldStyleFigures: "Old-Style Figures"
        case .variable: "Variable"
        }
    }

    /// What the suggestions find it by, lowercased: its title, the usual other words for it, and what kind of filter
    /// it is ("weight", "width", "numbers").
    var words: [String] {
        switch self {
        case .italic: ["italic", "italics", "oblique"]
        case .weight(let weight): [title.lowercased(), "weight"] + (Self.weights.first { $0.weight == weight }?.others ?? [])
        case .condensed: ["condensed", "compressed", "narrow", "width"]
        case .extended: ["extended", "expanded", "wide", "width"]
        case .tabularFigures: ["tabular figures", "tnum", "numbers", "numerals"]
        case .oldStyleFigures: ["old-style figures", "oldstyle figures", "old style figures", "onum", "numbers", "numerals"]
        case .variable: ["variable"]
        }
    }

    /// Tokens of a kind take each other's place: a style has one weight and one width.
    private var kind: Int {
        switch self {
        case .italic: 0
        case .weight: 1
        case .condensed, .extended: 2
        case .tabularFigures: 3
        case .oldStyleFigures: 4
        case .variable: 5
        }
    }

    /// The tokens with only the last of each kind, in their order.
    public static func normalized(_ tokens: [SearchToken]) -> [SearchToken] {
        tokens.indices.filter { index in !tokens[(index + 1)...].contains { $0.kind == tokens[index].kind } }.map { tokens[$0] }
    }

    /// The tokens to suggest for what's typed, but for those `chosen` already, each with what stays typed once it's
    /// chosen: those that the last words typed, two letters at least, begin a word of, the most of them that do, and
    /// the words before them stay ("sans ital" suggests Italic, leaving "sans").
    public static func suggestions(for typed: String, besides chosen: [SearchToken]) -> [(token: SearchToken, typed: String)] {
        let words = typed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return all.filter { !chosen.contains($0) }.compactMap { token in
            for start in words.indices {
                let run = words[start...].joined(separator: " ")
                if run.count >= 2, token.words.contains(where: { SearchQuery.beginsWord(run, in: $0) }) {
                    return (token, words[..<start].joined(separator: " "))
                }
            }
            return nil
        }
    }

    /// The style the tokens ask for, over the one the typed words name, if any: italic when either is, the tokens' weight
    /// and width before the words'. Nil when neither names one.
    static func style(of tokens: [SearchToken], over typed: SearchQuery.Style? = nil) -> SearchQuery.Style? {
        var style = typed ?? SearchQuery.Style()
        for token in tokens {
            switch token {
            case .italic: style.isItalic = true
            case .weight(let weight): style.weight = weight
            case .condensed: style.width = 3
            case .extended: style.width = 7
            case .tabularFigures, .oldStyleFigures, .variable: break
            }
        }
        return style == SearchQuery.Style() ? nil : style
    }

    /// The features previews turn on for the figures the tokens ask for, as the Info panel's Features tab sets them.
    public static func features(of tokens: [SearchToken]) -> [FeatureSetting] {
        tokens.compactMap { token in
            switch token {
            case .tabularFigures: FeatureSetting(type: kNumberSpacingType, selector: kMonospacedNumbersSelector)
            case .oldStyleFigures: FeatureSetting(type: kNumberCaseType, selector: kLowerCaseNumbersSelector)
            default: nil
            }
        }
    }
}

extension Family {
    /// Whether the family has what the tokens ask for: a style that's everything the style tokens say, italic, of the
    /// weight (a variable one whose weight axis reaches it, or one named for it), narrower or wider than normal, and
    /// variable for Variable; and the figures, in any of its styles.
    public func matches(_ tokens: [SearchToken]) -> Bool {
        if tokens.contains(.tabularFigures), !faces.contains(where: { $0.face.figures.contains(.tabular) }) { return false }
        if tokens.contains(.oldStyleFigures), !faces.contains(where: { $0.face.figures.contains(.oldStyle) }) { return false }
        let variable = tokens.contains(.variable)
        if variable, !isVariable { return false }
        guard let style = SearchToken.style(of: tokens) else { return true }
        return faces.contains { library in
            let face = library.face
            if variable && face.axes.isEmpty { return false }
            if style.isItalic && !face.isItalic { return false }
            if let width = style.width, (widthClass(of: face) - 5).signum() != (width - 5).signum() { return false }
            guard let weight = style.weight else { return true }
            if let axis = face.weightAxis, axis.minimum <= Double(weight), Double(weight) <= axis.maximum { return true }
            return FontFace.hundreds(face.namedWeight) == weight
        }
    }
}
