import CiceroCore
import Foundation
import FoundationModels

final class ClassificationGuesser {
    private(set) var guesses: [String: Classification]

    private let url: URL
    private var pending: [Question] = []
    private var task: Task<Void, Never>?
    private var failed: Set<String> = []

    init(caches: URL) {
        url = ClassificationGuesses.namesFile(caches: caches)
        guesses = ClassificationGuesses.savedNames(caches: caches)
    }

    enum Availability { case available, notEnabled, notReady, unavailable }

    static var availability: Availability {
        guard #available(macOS 26, *) else { return .unavailable }
        return switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .notEnabled
        case .unavailable(.modelNotReady): .notReady
        case .unavailable: .unavailable
        }
    }

    static var readsNames: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    func guess(_ families: [Family], found: @escaping () -> Void) {
        pending = families.filter { guesses[$0.id] == nil && !failed.contains($0.id) }.map(Question.init)
        guard task == nil, !pending.isEmpty, Self.availability == .available else { return }
        task = Task { [weak self] in await self?.work(found: found) }
    }

    func forget() {
        task?.cancel()
        task = nil
        pending = []
        failed = []
        guesses = [:]
        try? FileManager.default.removeItem(at: url)
    }

    private func work(found: @escaping () -> Void) async {
        guard #available(macOS 26, *) else { return }
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
            guard guesses[question.name] == nil else { continue }
            let outcome = await Self.ask(question)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .answer(let classification):
                guesses[question.name] = classification
                if classification != .unclassified { changed = true }
            case .notNow:
                failed.insert(question.name)
            case .later:
                pending = []
            }
            if ContinuousClock.now - reported > .seconds(1) { report() }
        }
        report()
        task = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ClassificationGuesses.SavedNames(guesses: guesses)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Asking

    private struct Question {
        var name: String
        var foundry: String?
        var designer: String?
        var styles: [String]

        init(_ family: Family) {
            // As the fonts give it, not as shown in the Mac's language.
            name = family.id
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

    @available(macOS 26, *)
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
        case notNow
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

    @available(macOS 26, *)
    private static func ask(_ question: Question) async -> Outcome {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(to: question.prompt, generating: Kind.self, options: GenerationOptions(samplingMode: .greedy))
            return .answer(response.content.classification)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return .later
            case .guardrailViolation, .refusal, .decodingFailure, .unsupportedLanguageOrLocale, .exceededContextWindowSize: return .answer(.unclassified)
            default: return .notNow
            }
        } catch {
            return .notNow
        }
    }
}
