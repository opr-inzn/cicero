import CryptoKit
import Foundation

/// What Spotlight knows about one family: what only Cicero knows of it (its classification, foundry as the user names
/// it, tags, rating, sets and smart sets) and every style's names. macOS's own importer already puts every font file's
/// names, designer and foundry in Spotlight, as files.
///
/// One item per family, with its styles' names among its keywords, rather than an item per style: a style's
/// PostScript or full name ("HelveticaNeue-BoldItalic", "Helvetica Neue Bold Italic") finds its family all the same,
/// while styles as items of their own crowd the families out of the few results a search gives an app. Core
/// Spotlight's own user query stops at 40: with styles as items, a family's name gave 40 of its styles and not the
/// family. They'd also be 6.5 times the items (7,637 for 1,180 families).
public struct SpotlightEntry: Hashable, Sendable {
    /// The family's name, its id in the library.
    public var family: String
    /// "Serif · Carter & Cone · Licensed · ★★★★", under the name in Spotlight's results.
    public var description: String
    /// Words that find it besides its name: classification, foundry, designers, tags, sets and smart sets, and its
    /// styles' names, full names and PostScript names.
    public var keywords: [String]
    /// The style its thumbnail is set in: the family's regular one.
    public var sample: FontFace

    public init(family: String, description: String, keywords: [String], sample: FontFace) {
        self.family = family
        self.description = description
        self.keywords = keywords
        self.sample = sample
    }

    /// The family as the browser shows it (see `SpotlightFacts`).
    public init(family: Family, facts: SpotlightFacts) {
        let faces = family.faces.map(\.face)
        let stars = facts.rating.map { String(repeating: "★", count: min(max($0, 0), 5)) }
        func unique(_ words: [String?]) -> [String] {
            var seen = Set<String>()
            return words.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        self.init(
            family: family.id,
            description: unique([facts.classification, facts.foundry] + facts.tags + [stars]).joined(separator: " · "),
            keywords: unique([facts.classification, facts.foundry, family.manufacturer] + faces.map(\.designer) + faces.map(\.vendorID)
                + facts.tags + facts.sets + facts.smartSets + faces.map(\.styleName) + faces.map(\.fullName) + faces.map(\.postScriptName)),
            sample: family.regular.face
        )
    }

    /// The entries of these families, made off the caller's thread: their keywords are every style's names, tens of
    /// thousands of words in a large library.
    @concurrent
    public static func entries(_ families: [(Family, SpotlightFacts)]) async -> [SpotlightEntry] {
        families.map { SpotlightEntry(family: $0, facts: $1) }
    }

    /// Its item's identifier in Spotlight, which comes back when the item is opened.
    public var identifier: String { Self.identifier(forFamily: family) }

    public static func identifier(forFamily family: String) -> String { prefix + family }

    /// The family an item's identifier stands for; nil for an identifier that isn't a family's.
    public static func family(fromIdentifier identifier: String) -> String? {
        identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : nil
    }

    private static let prefix = "family:"

    /// Changes when anything Spotlight shows of the family does, the sample's file included, which a type designer
    /// exports again and again under the same names. The same in every launch, unlike `hashValue`.
    func digest(sampleStamp: String) -> String {
        var text = [family, description, sample.id.description, sample.postScriptName, sampleStamp].joined(separator: "\u{1E}")
        text += "\u{1E}" + keywords.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the app knows of a family that Spotlight shows, and the files don't say.
public struct SpotlightFacts: Sendable {
    /// Its classification's name, as the user named it; nil when it's unclassified.
    public var classification: String?
    /// Its foundry, as the user named it.
    public var foundry: String?
    /// Its tags, in the user's order.
    public var tags: [String]
    public var rating: Int?
    /// The names of the sets and smart sets it's in.
    public var sets: [String]
    public var smartSets: [String]

    public init(classification: String? = nil, foundry: String? = nil, tags: [String] = [], rating: Int? = nil,
                sets: [String] = [], smartSets: [String] = []) {
        self.classification = classification
        self.foundry = foundry
        self.tags = tags
        self.rating = rating
        self.sets = sets
        self.smartSets = smartSets
    }
}

extension UserData {
    /// Whether Spotlight's items would differ: what they say of a family, or which families are listed. Not activation
    /// records, which change whenever a font is turned on or off, and whose results the scan after brings.
    public func showsDifferentlyInSpotlight(than other: UserData) -> Bool {
        sets != other.sets || smartSets != other.smartSets || tags != other.tags || familyTags != other.familyTags
            || familyRatings != other.familyRatings || foundryOverrides != other.foundryOverrides || foundryRenames != other.foundryRenames
            || classifications != other.classifications || classificationOverrides != other.classificationOverrides
            || classificationRenames != other.classificationRenames || showSystemFonts != other.showSystemFonts
            || showCreativeCloudFonts != other.showCreativeCloudFonts || customCharacterSets != other.customCharacterSets
    }
}
