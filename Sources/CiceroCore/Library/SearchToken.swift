import CoreText
import Foundation

public enum SearchToken: Hashable, Identifiable, Sendable {
    case italic
    case weight(Int)
    case condensed
    case extended
    case tabularFigures
    case oldStyleFigures
    case variable

    public var id: Self { self }

    public static let all: [SearchToken] = [.italic] + weights.map { .weight($0.weight) } + [.condensed, .extended, .tabularFigures, .oldStyleFigures, .variable]

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

    public static func named(_ word: String) -> SearchToken? {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        if let weight = Int(word), weights.contains(where: { $0.weight == weight }) { return .weight(weight) }
        let kinds: Set<String> = ["weight", "width", "numbers", "numerals"]
        guard !kinds.contains(word) else { return nil }
        return all.first { $0.words.contains(word) }
    }

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

    public static func normalized(_ tokens: [SearchToken]) -> [SearchToken] {
        tokens.indices.filter { index in !tokens[(index + 1)...].contains { $0.kind == tokens[index].kind } }.map { tokens[$0] }
    }

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
