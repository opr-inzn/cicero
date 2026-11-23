import Foundation

public enum ClassificationGuesses {
    public static let guessingKey = "classification.guessesFromNames"
    public static let askingKey = "classification.asksAboutGuessing"
    public static let letterLikelihood: Float = 0.7
    public static let namesVersion = 1

    public static func namesFile(caches: URL) -> URL {
        caches.appendingPathComponent("classification-guesses.json", isDirectory: false)
    }

    public struct SavedNames: Codable, Sendable {
        public var version: Int
        public var guesses: [String: Classification]

        public init(version: Int = ClassificationGuesses.namesVersion, guesses: [String: Classification]) {
            self.version = version
            self.guesses = guesses
        }
    }

    public static func savedNames(caches: URL) -> [String: Classification] {
        let saved = (try? Data(contentsOf: namesFile(caches: caches))).flatMap { try? JSONDecoder().decode(SavedNames.self, from: $0) }
        return saved.flatMap { $0.version == namesVersion ? $0.guesses : nil } ?? [:]
    }

    public static func isGuessing(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: askingKey) && defaults.object(forKey: guessingKey) as? Bool ?? true
    }

    public static func letters(of families: [Family], measurements: MeasurementIndex) -> [String: Classification] {
        var found: [String: Classification] = [:]
        for family in families where family.classification == .unclassified && !family.mixesSerifAndSans {
            guard let seen = measurements.classification(of: family.regular.face.id), seen.likelihood >= letterLikelihood else { continue }
            found[family.id] = seen.classification
        }
        return found
    }

    public enum Source: Sendable {
        case name
        case letters
    }

    public static func rule(names: [String: Classification], letters: [String: Classification], guessing: Bool)
        -> (Family) -> (classification: Classification, source: Source)? {
        { family in
            guard guessing, family.classification == .unclassified, !family.mixesSerifAndSans else { return nil }
            if let guess = names[family.id], guess != .unclassified { return (guess, .name) }
            return letters[family.id].map { ($0, .letters) }
        }
    }
}
