import CiceroCore
import Foundation
import Observation

@Observable
final class SampleSources {
    static let shared = SampleSources()
    private static let recentKey = "sampleSources.recentLanguages"

    private(set) var recent: [String] { didSet { UserDefaults.standard.set(recent, forKey: Self.recentKey) } }
    private var fetched: [(article: WikipediaArticle, opening: String)] = []
    private(set) var loading = 0
    private var request: Task<Void, Never>?
    let macLanguages: [String]

    private init() {
        var mac: [String] = []
        for language in Locale.preferredLanguages.compactMap(Wikipedia.language(for:)) where !mac.contains(language) { mac.append(language) }
        if mac.isEmpty { mac = ["en"] }
        macLanguages = mac
        recent = Array((UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [])
            .filter { Wikipedia.languages.contains($0) && !mac.contains($0) }.prefix(3))
    }

    func start(_ work: @escaping () async -> Void) {
        request?.cancel()
        request = Task { await work() }
    }

    var shortList: [String] {
        macLanguages + recent
    }

    func article(in language: String) async throws -> WikipediaArticle {
        loading += 1
        defer { loading -= 1 }
        let article = try await Wikipedia.randomArticle(in: language)
        if !macLanguages.contains(language) {
            recent = Array(([language] + recent.filter { $0 != language && !macLanguages.contains($0) }).prefix(3))
        }
        fetched = Array(([(article, article.opening)] + fetched).prefix(16))
        return article
    }

    func source(of text: String) -> WikipediaArticle? {
        fetched.first { text == $0.article.text || text == $0.opening }?.article
    }

    static func name(of language: String) -> String {
        let english = Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language
        guard let own = Locale(identifier: language).localizedString(forLanguageCode: language), !own.isEmpty else { return english }
        let capitalized = own.prefix(1).uppercased(with: Locale(identifier: language)) + own.dropFirst()
        return capitalized.localizedCaseInsensitiveCompare(english) == .orderedSame ? english : "\(capitalized) (\(english))"
    }

    static let byName: [String] = Wikipedia.languages.sorted {
        (Locale(identifier: "en").localizedString(forLanguageCode: $0) ?? $0)
            .localizedStandardCompare(Locale(identifier: "en").localizedString(forLanguageCode: $1) ?? $1) == .orderedAscending
    }
}
