import Foundation

public enum Pangrams {
    public static let all = [
        "The quick brown fox jumps over the lazy dog.",
        "Sphinx of black quartz, judge my vow.",
        "Pack my box with five dozen liquor jugs.",
        "Jackdaws love my big sphinx of quartz.",
        "The five boxing wizards jump quickly.",
        "How vexingly quick daft zebras jump!",
        "Bright vixens jump; dozy fowl quack.",
        "Quick zephyrs blow, vexing daft Jim.",
        "Waltz, bad nymph, for quick jigs vex.",
        "Glib jocks quiz nymph to vex dwarf.",
        "Two driven jocks help fax my big quiz.",
        "Five quacking zephyrs jolt my wax bed.",
        "The jay, pig, fox, zebra and my wolves quack!",
        "Blowzy red vixens fight for a quick jump.",
        "Amazingly few discotheques provide jukeboxes.",
        "Heavy boxes perform quick waltzes and jigs.",
        "Jinxed wizards pluck ivy from the big quilt.",
        "Crazy Frederick bought many very exquisite opal jewels.",
        "We promptly judged antique ivory buckles for the next prize.",
        "A mad boxer shot a quick, gloved jab to the jaw of his dizzy opponent.",
        "Big fjords vex quick waltz nymph.",
        "Quick fox jumps nightly above wizard.",
        "Few quips galvanized the mock jury box.",
        "Woven silk pyjamas exchanged for blue quartz.",
        "Six big devils from Japan quickly forgot how to waltz.",
        "The quick onyx goblin jumps over the lazy dwarf.",
        "Public junk dwarves quiz mighty fox.",
        "Sixty zippers were quickly picked from the woven jute bag.",
        "Just keep examining every low bid quoted for zinc etchings.",
        "My girl wove six dozen plaid jackets before she quit.",
        "The wizard quickly jinxed the gnomes before they vaporized.",
        "A quick movement of the enemy will jeopardize six gunboats.",
        "All questions asked by five watched experts amaze the judge.",
        "Back in June we delivered oxygen equipment of the same size.",
        "Jack quietly moved up front and seized the big ball of wax.",
        "Pack my red box with five dozen quality jugs.",
        "Grumpy wizards make a toxic brew for the jovial queen.",
        "Jumpy halfling dwarves pick quartz box.",
        "Fickle jinx bog dwarves spy math quiz.",
        "Waxy and quivering, jocks fumble the pizza.",
    ]

    public static func random(other current: String) -> String {
        all.filter { $0 != current }.randomElement() ?? all[0]
    }
}

public struct WikipediaArticle: Hashable, Sendable {
    public let language: String
    public let title: String
    public let text: String
    public let url: URL

    public var opening: String {
        let wide = Wikipedia.wideLanguages.contains(language)
        let length = wide ? 30 : 60, maximum = wide ? 55 : 110
        let start = text.startIndex
        func count(to end: String.Index) -> Int { text[start..<end].trimmingCharacters(in: .whitespaces).count }
        var end = start
        text.enumerateSubstrings(in: start..., options: .bySentences) { _, range, _, stop in
            if end > start, count(to: range.upperBound) > maximum {
                stop = true
            } else {
                end = range.upperBound
                stop = count(to: end) >= length
            }
        }
        guard count(to: end) > maximum else { return String(text[..<end]).trimmingCharacters(in: .whitespaces) }
        // Thai and Lao end sentences with a space, not a stop, so their first sentence can be the whole paragraph.
        var cut = start
        text.enumerateSubstrings(in: start..<end, options: .byWords) { _, range, _, stop in
            if text.distance(from: start, to: range.upperBound) > maximum {
                stop = true
            } else {
                cut = range.upperBound
            }
        }
        if cut == start { cut = text.index(start, offsetBy: maximum) }
        return String(text[..<cut]).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public enum Wikipedia {
    public static let languages = [
        "af", "ar", "az", "be", "bg", "bn", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "eo", "es", "et", "eu", "fa",
        "fi", "fr", "ga", "gl", "gu", "he", "hi", "hr", "hu", "hy", "id", "is", "it", "ja", "ka", "kk", "km", "kn", "ko",
        "lt", "lv", "mk", "ml", "mn", "mr", "ms", "my", "ne", "nl", "no", "pa", "pl", "pt", "ro", "ru", "si", "sk", "sl",
        "sq", "sr", "sv", "sw", "ta", "te", "th", "tl", "tr", "uk", "ur", "uz", "vi", "zh",
    ]

    static let wideLanguages: Set = ["ja", "ko", "zh"]

    public enum Failure: Error {
        case noAnswer
    }

    public static func language(for identifier: String) -> String? {
        guard var code = Locale.Language(identifier: identifier).languageCode?.identifier else { return nil }
        // The Wikipedias for Norwegian Bokmål and Filipino are no and tl, not nb and fil.
        if code == "nb" { code = "no" }
        if code == "fil" { code = "tl" }
        return languages.contains(code) ? code : nil
    }

    public static func randomArticle(in language: String) async throws -> WikipediaArticle {
        guard languages.contains(language),
              let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/random/summary")
        else { throw Failure.noAnswer }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("Cicero/\(version) (https://cicero.maximilianinzinger.com)", forHTTPHeaderField: "User-Agent")
        let minimum = wideLanguages.contains(language) ? 30 : 80
        for _ in 0..<6 {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 { continue }
            guard status == 200 else { throw Failure.noAnswer }
            guard let summary = try? JSONDecoder().decode(Summary.self, from: data),
                  summary.type == "standard", let title = summary.title,
                  let text = summary.extract?.split(whereSeparator: \.isWhitespace).joined(separator: " "), text.count >= minimum,
                  let page = summary.content_urls?.desktop.page.flatMap(URL.init(string:)), page.scheme == "https"
            else { continue }
            return WikipediaArticle(language: language, title: title, text: text, url: page)
        }
        throw Failure.noAnswer
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    private struct Summary: Decodable {
        struct Links: Decodable {
            struct Page: Decodable { let page: String? }
            let desktop: Page
        }
        let type: String?
        let title: String?
        let extract: String?
        let content_urls: Links?
    }
}
