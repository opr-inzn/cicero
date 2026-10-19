import CiceroCore
import Foundation
import FoundationModels

/// Classifications for the families nothing in their files classifies (see `Classification.of`), guessed from
/// their names by the language model Apple Intelligence keeps on the Mac, while Settings → General → Guess
/// classifications is on; they come before the model of letters' guesses (see `AppModel.letterGuesses`), as the
/// language model answers only when a name says. The model runs on the Mac, so nothing is sent anywhere. Each family
/// is asked about once, one at a time in the background; the answers, "can't tell" among them, are kept in the caches.
final class ClassificationGuesser {
    /// Family name → the model's guess; `.unclassified` where it couldn't tell.
    private(set) var guesses: [String: Classification]

    private let url: URL
    private var pending: [Question] = []
    private var task: Task<Void, Never>?
    /// Families the model failed to answer for, in a way that may not last; asked again at the next launch.
    private var failed: Set<String> = []

    /// Raised when the questions change, so the answers to the old ones are asked again.
    private static let version = 1

    private struct Saved: Codable {
        var version: Int
        var guesses: [String: Classification]
    }

    init(caches: URL) {
        url = caches.appendingPathComponent("classification-guesses.json", isDirectory: false)
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        guesses = saved?.version == Self.version ? saved!.guesses : [:]
    }

    static var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }

    /// Asks about the families that have no guess yet, in place of any it hasn't got to. `found` is called as
    /// guesses come, a few at a time.
    func guess(_ families: [Family], found: @escaping () -> Void) {
        pending = families.filter { guesses[$0.id] == nil && !failed.contains($0.id) }.map(Question.init)
        guard task == nil, !pending.isEmpty, case .available = Self.availability else { return }
        task = Task { [weak self] in await self?.work(found: found) }
    }

    /// Stops asking and forgets every guess.
    func forget() {
        task?.cancel()
        task = nil
        pending = []
        failed = []
        guesses = [:]
        try? FileManager.default.removeItem(at: url)
    }

    private func work(found: @escaping () -> Void) async {
        var reported = ContinuousClock.now
        var changed = false
        func report() {
            save()
            if changed { found() }
            changed = false
            reported = .now
        }
        while !pending.isEmpty {
            let question = pending.removeFirst()
            // Asked for again while it was being asked about.
            guard guesses[question.name] == nil else { continue }
            let outcome = await Self.ask(question)
            // Forgotten meanwhile: another task may be asking already.
            guard !Task.isCancelled else { return }
            switch outcome {
            case .answer(let classification):
                guesses[question.name] = classification
                if classification != .unclassified { changed = true }
            case .notNow:
                failed.insert(question.name)
            case .later:
                // Busy, or the model went away: the next scan asks again.
                pending = []
            }
            if ContinuousClock.now - reported > .seconds(1) { report() }
        }
        report()
        task = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(version: Self.version, guesses: guesses)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Asking

    /// What the model is told about a family.
    private struct Question {
        var name: String
        var foundry: String?
        var designer: String?
        var styles: [String]

        init(_ family: Family) {
            name = family.name
            foundry = family.manufacturer
            designer = family.faces.lazy.compactMap(\.face.designer).first
            var seen = Set<String>()
            styles = Array(family.faces.map(\.face.styleName).filter { seen.insert($0).inserted }.prefix(12))
        }

        var prompt: String {
            var lines = ["Font family: \(name)"]
            if let foundry { lines.append("Foundry: \(foundry)") }
            if let designer { lines.append("Designer: \(designer)") }
            if !styles.isEmpty { lines.append("Styles: " + styles.joined(separator: ", ")) }
            return lines.joined(separator: "\n")
        }
    }

    @Generable
    nonisolated enum Kind {
        case serif, sansSerif, monospaced, script, ornamental, symbol, unknown

        var classification: Classification {
            switch self {
            case .serif: .serif
            case .sansSerif: .sansSerif
            case .monospaced: .monospaced
            case .script: .script
            case .ornamental: .ornamental
            case .symbol: .symbol
            case .unknown: .unclassified
            }
        }
    }

    private enum Outcome {
        case answer(Classification)
        /// No answer this time, but there may be one at another.
        case notNow
        /// No answer to any question for now.
        case later
    }

    private static let instructions = """
        You tell what kind of typeface a font family is, from its name and the little else that's known about it. \
        The kinds are:
        serif: letters with serifs, slab serifs among them
        sansSerif: letters without serifs
        monospaced: every character as wide as the others, as for code and typewriters
        script: handwriting, calligraphy, brush and signature lettering
        ornamental: decorative display lettering, blackletter, stencils, outlined and novelty letters
        symbol: pictures, dingbats, icons or mathematical signs rather than letters
        unknown: when you can't tell
        Words like Trial, Test, Unlicensed, Variable, VF, Pro, Std, Display and Text say nothing about the kind. \
        A font for a script other than Latin is unknown unless its name says what kind it is. \
        Answer unknown rather than guess.
        """

    private static func ask(_ question: Question) async -> Outcome {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(to: question.prompt, generating: Kind.self, options: GenerationOptions(samplingMode: .greedy))
            return .answer(response.content.classification)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return .later
            // Names the model won't talk about, or can't make sense of.
            case .guardrailViolation, .refusal, .decodingFailure, .unsupportedLanguageOrLocale, .exceededContextWindowSize: return .answer(.unclassified)
            default: return .notNow
            }
        } catch {
            return .notNow
        }
    }
}
