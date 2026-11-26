import CiceroCore
import Foundation
import Observation

@Observable
final class SampleSources {
    static let shared = SampleSources()
    static let previewLength = 60
    private static let languageKey = "sampleSources.wikipediaLanguage"
    private static let recentKey = "sampleSources.recentLanguages"

    private(set) var language: String { didSet { UserDefaults.standard.set(language, forKey: Self.languageKey) } }
    private(set) var recent: [String] { didSet { UserDefaults.standard.set(recent, forKey: Self.recentKey) } }
    private(set) var article: WikipediaArticle?
    private(set) var loading = 0
    let macLanguages: [String]

    private init() {
        var mac: [String] = []
        for language in Locale.preferredLanguages.compactMap(Wikipedia.language(for:)) where !mac.contains(language) { mac.append(language) }
        macLanguages = mac.isEmpty ? ["en"] : mac
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Self.languageKey).flatMap { Wikipedia.languages.contains($0) ? $0 : nil } ?? macLanguages[0]
        recent = (defaults.stringArray(forKey: Self.recentKey) ?? []).filter(Wikipedia.languages.contains)
    }

    var shortList: [String] {
        macLanguages + recent.filter { !macLanguages.contains($0) }.prefix(3)
    }

    func article(in language: String) async throws -> WikipediaArticle {
        loading += 1
        defer { loading -= 1 }
        let article = try await Wikipedia.randomArticle(in: language)
        self.language = language
        if !macLanguages.contains(language) {
            recent = Array(([language] + recent.filter { $0 != language }).prefix(3))
        }
        self.article = article
        return article
    }

    func source(of text: String) -> WikipediaArticle? {
        guard let article, text == article.text || text == article.opening(length: Self.previewLength) else { return nil }
        return article
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
