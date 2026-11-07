import Foundation

/// The guessed classifications of families nothing in their files classifies, for the app and the `cicero` tool alike:
/// Apple Intelligence's from their names, kept in the caches (`classification-guesses.json`, which the app's
/// `ClassificationGuesser` writes), else what the model of letters sees in them (see `MeasurementIndex.classification`).
public enum ClassificationGuesses {
    /// The user default that says whether guessing is on (Settings → General → Classify fonts automatically).
    public static let guessingKey = "classification.guessesFromNames"
    /// The user default set while the app still asks whether to guess; nothing is guessed meanwhile.
    public static let askingKey = "classification.asksAboutGuessing"
    /// How sure the model of letters must be of a classification for it to count: a wrong classification is worse than none.
    public static let letterLikelihood: Float = 0.7
    /// Raised when the questions to the language model change, so the answers to the old ones are asked again.
    public static let namesVersion = 1

    /// Where the guesses from names are kept.
    public static func namesFile(caches: URL) -> URL {
        caches.appendingPathComponent("classification-guesses.json", isDirectory: false)
    }

    /// What `namesFile` holds.
    public struct SavedNames: Codable, Sendable {
        public var version: Int
        /// Family name → the model's guess; `.unclassified` where it couldn't tell.
        public var guesses: [String: Classification]

        public init(version: Int = ClassificationGuesses.namesVersion, guesses: [String: Classification]) {
            self.version = version
            self.guesses = guesses
        }
    }

    /// The guesses from names as saved; none from another version of the questions, or without a file.
    public static func savedNames(caches: URL) -> [String: Classification] {
        let saved = (try? Data(contentsOf: namesFile(caches: caches))).flatMap { try? JSONDecoder().decode(SavedNames.self, from: $0) }
        return saved.flatMap { $0.version == namesVersion ? $0.guesses : nil } ?? [:]
    }

    /// Whether guessing is on, as the app decides it at launch: off while it still asks, else on unless turned off.
    public static func isGuessing(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: askingKey) && defaults.object(forKey: guessingKey) as? Bool ?? true
    }

    /// The classifications the model of letters sees in the families nothing in their files classifies, where it's
    /// sure enough.
    public static func letters(of families: [Family], measurements: MeasurementIndex) -> [String: Classification] {
        var found: [String: Classification] = [:]
        for family in families where family.classification == .unclassified && !family.mixesSerifAndSans {
            guard let seen = measurements.classification(of: family.regular.face.id), seen.likelihood >= letterLikelihood else { continue }
            found[family.id] = seen.classification
        }
        return found
    }

    /// Where a guess comes from.
    public enum Source: Sendable {
        /// Apple Intelligence, from the family's name.
        case name
        /// The model of letters, from their shapes.
        case letters
    }

    /// The guess for a family its fonts don't classify, and where it comes from: the name's, which the language model
    /// makes only when the name says, else the letters'; nothing while guessing is off, and nothing for a family whose
    /// letters say serif for some styles and sans serif for others.
    public static func rule(names: [String: Classification], letters: [String: Classification], guessing: Bool)
        -> (Family) -> (classification: Classification, source: Source)? {
        { family in
            guard guessing, family.classification == .unclassified, !family.mixesSerifAndSans else { return nil }
            if let guess = names[family.id], guess != .unclassified { return (guess, .name) }
            return letters[family.id].map { ($0, .letters) }
        }
    }
}
