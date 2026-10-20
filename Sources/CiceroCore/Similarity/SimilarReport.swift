import Foundation

/// What Cicero sends when the user says families listed among another's similar fonts don't look like it, so that the
/// model and the weights can learn to set them apart: the family the list is for and the list as the user saw it, each
/// family by its names and the numbers the list was made from (its letter measurements and embedding). No font files,
/// nor pictures of letters.
public struct SimilarReport: Codable, Equatable, Sendable {
    /// One family as the list saw it.
    public struct Entry: Codable, Equatable, Sendable {
        /// The family's own name, as its fonts have it (`Family.id`).
        public var name: String
        /// The PostScript name of the style it was measured by, its regular.
        public var style: String
        public var foundry: String?
        /// As the sidebar has it, the user's own and guesses included; nil for Unclassified.
        public var classification: String?
        /// Its `LetterMeasurements` by measure, those it has.
        public var measurements: [String: Float]
        /// Its `LetterEmbedding`; nil without.
        public var embedding: [Float]?
        /// How far it is from the family the list is for (`SimilarFonts.nearestWithDistances`); nil for that family.
        public var distance: Float?

        public init(name: String, style: String, foundry: String?, classification: String?, measurements: LetterMeasurements?,
                    embedding: [Float]?, distance: Float?) {
            self.name = name
            self.style = style
            self.foundry = foundry
            self.classification = classification
            var values: [String: Float] = [:]
            for measure in LetterMeasurements.Measure.allCases {
                if let value = measurements?[measure], !value.isNaN { values[String(describing: measure)] = value }
            }
            self.measurements = values
            self.embedding = embedding
            self.distance = distance
        }
    }

    /// Where the list was.
    public enum Place: String, Codable, Sendable {
        /// A font page's Similar.
        case page
        /// Show Similar Fonts, in the browser.
        case browser
    }

    /// Raised when what a report holds changes.
    public var format = 1
    public var app: String
    public var build: String
    public var macOS: String
    /// `MeasurementIndex.version`: which measurements and which model the numbers are from.
    public var model: Int
    /// A hash of a random number kept on the Mac, so that a pair reported on many Macs can count for more than one
    /// reported many times on one.
    public var mac: String
    /// A build without a team's signature, a test's.
    public var test: Bool
    public var shownIn: Place
    /// The family the list is for.
    public var family: Entry
    /// The names of the families the user said don't look like it, from `list`.
    public var notSimilar: [String]
    /// The list as the user saw it, the nearest first, as long as Show Similar Fonts' (`SimilarFonts.longestList`), those
    /// in `notSimilar` among them.
    public var list: [Entry]

    public init(app: String, build: String, macOS: String, mac: String, test: Bool, shownIn: Place, family: Entry,
                notSimilar: [String], list: [Entry]) {
        self.app = app
        self.build = build
        self.macOS = macOS
        model = MeasurementIndex.version
        self.mac = mac
        self.test = test
        self.shownIn = shownIn
        self.family = family
        self.notSimilar = notSimilar
        self.list = list
    }
}
