import CiceroCore
import Foundation

/// `cicero find [words] [filters]`, and `cicero list families`: families, as the app's search finds them, with filters
/// for what the sidebar and smart folders test.
public struct FindOptions: Sendable {
    public enum Sort: String, CaseIterable, Sendable {
        /// A to Z, by the name shown.
        case name
        /// The latest first, by when the family arrived on the Mac.
        case added
        /// The latest first, by the year its earliest style came out; families without one last.
        case released
    }

    public var words: [String] = []
    /// Families any of `words` finds, each word (or quoted phrase) a search of its own; else all of them, together.
    public var any = false
    public var foundry: String?
    public var classification: String?
    /// "2019", "2015..2020", "2015..", "..2020".
    public var released: String?
    /// "2024", "2024-03", "2024-03-15", or a range of them with "..".
    public var added: String?
    public var text: String?
    public var set: String?
    /// How many characters of `text` or `set` a family may lack.
    public var missing: Int?
    public var tag: String?
    public var folder: String?
    public var location: String?
    public var active = false
    public var inactive = false
    public var sort: Sort?
    /// Style words, as the search field's tokens (see `SearchToken.named`).
    public var filters: [String] = []
    /// 0: all.
    public var limit = 50
    public var offset = 0

    public init() {}
}

public enum FindCommand {
    public static func run(_ options: FindOptions, in context: LibraryContext) throws -> JSON {
        guard options.limit >= 0 else { throw CommandError.invalid("--limit can’t be less than 0.") }
        guard options.offset >= 0 else { throw CommandError.invalid("--offset can’t be less than 0.") }
        let found = try families(options, in: context)
        let page = options.limit == 0 ? found.dropFirst(options.offset) : found.dropFirst(options.offset).prefix(options.limit)
        let describer = Describer(context)
        var answer = JSONObject.answer()
        answer.set("families", page.map { describer.family($0).json })
        answer.set("total", found.count)
        answer.set("limit", options.limit)
        answer.set("offset", options.offset)
        return answer.json
    }

    /// The families that match, in the order asked for.
    public static func families(_ options: FindOptions, in context: LibraryContext) throws -> [Family] {
        if options.any, options.words.allSatisfy({ SearchQuery($0).isEmpty }) {
            throw CommandError.invalid("--any goes with words: cicero find trial unlicensed test --any.")
        }
        let tests = try filters(options, in: context)
        let base = context.listedFamilies.filter { family in tests.allSatisfy { $0(family) } }
        let tokens = try options.filters.map { try token($0, in: context) }
        // With --any, each word (or phrase in quotes, one argument) is a search of its own, and a family any of them finds
        // is found; else the words are one search, as typed in the search field.
        let queries = options.any ? options.words.map(SearchQuery.init).filter { !$0.isEmpty } : [SearchQuery(options.words.joined(separator: " "))]
        let hasWords = queries.contains { !$0.isEmpty }
        // Unlike the app's search field (for now), words are looked for in the fonts' licenses, descriptions and URLs too,
        // read from the files of the families the options leave.
        let texts = hasWords ? fileTexts(base) : [:]
        func found(_ queries: [SearchQuery], moreTexts: @escaping (Family) -> [String]) -> [Family] {
            let matchers = queries.map { context.filters.searchMatcher($0, tokens: tokens, moreTexts: moreTexts) }
            return base.filter { family in matchers.contains { $0(family) } }
        }
        var families = found(queries, moreTexts: { texts[$0.id] ?? [] })
        // Nothing with a word that begins with what's typed: a piece of a longer word, then, as in the app ("vetica").
        if families.isEmpty, hasWords { families = found(queries.map(\.anywhereInNames), moreTexts: { _ in [] }) }
        return sorted(families, by: options.sort)
    }

    /// Each family's licenses, license URLs, descriptions, and manufacturer and designer URLs, lowercased, each once.
    static func fileTexts(_ families: [Family]) -> [String: [String]] {
        let names = FileNames.read(families.flatMap { $0.faces.map(\.face) })
        var texts: [String: [String]] = [:]
        for family in families {
            var seen = Set<String>()
            texts[family.id] = family.faces.flatMap { face -> [String] in
                guard let read = names[face.face.id] else { return [] }
                return [read.license, read.licenseURL, read.description, read.manufacturerURL, read.designerURL].compactMap { $0?.lowercased() }
            }.filter { seen.insert($0).inserted }
        }
        return texts
    }

    static func sorted(_ families: [Family], by sort: FindOptions.Sort?) -> [Family] {
        switch sort {
        case nil: return families
        case .name:
            return families.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .added:
            return families.enumerated().sorted { a, b in
                let (x, y) = (a.element.dateAdded ?? .distantPast, b.element.dateAdded ?? .distantPast)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        case .released:
            return families.enumerated().sorted { a, b in
                let (x, y) = (a.element.year ?? Int.min, b.element.year ?? Int.min)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
    }

    /// The token a `--filter` word names.
    static func token(_ word: String, in context: LibraryContext) throws -> SearchToken {
        if let token = SearchToken.named(word) { return token }
        if context.characterSet(word) != nil {
            throw CommandError.invalid("“\(word)” isn’t a style word. For a coverage set, use --set \(word).")
        }
        throw CommandError(.invalidArgument, "“\(word)” isn’t a style word. Use one of these.", suggestions: SearchToken.all.map { $0.title.lowercased() })
    }

    /// The tests of every filter given but the words and style words.
    static func filters(_ options: FindOptions, in context: LibraryContext) throws -> [(Family) -> Bool] {
        var tests: [(Family) -> Bool] = []
        let filters = context.filters
        if let foundry = options.foundry {
            let names = Set(context.listedFamilies.compactMap(context.foundryName))
            let name = try exact(foundry, among: names, kind: "foundry")
            let foundryName = context.foundryName
            tests.append { foundryName($0) == name }
        }
        if let classification = options.classification {
            let name = try exact(classification, among: Set(context.data.classificationNames), kind: "class")
            tests.append(filters.filter(for: .classification(name)))
        }
        if let released = options.released {
            let range = try years(released)
            tests.append { family in family.year.map(range.contains) ?? false }
        }
        if let added = options.added {
            let range = try dates(added)
            tests.append { family in family.dateAdded.map { range.lowerBound <= $0 && $0 < range.upperBound } ?? false }
        }
        if options.missing != nil, options.text == nil, options.set == nil {
            throw CommandError.invalid("--missing goes with --text or --set.")
        }
        let missing = options.missing ?? 0
        guard missing >= 0 else { throw CommandError.invalid("--missing can’t be less than 0.") }
        if let text = options.text {
            let scalars = CoverageSearch.scalars(in: text).sorted()
            guard !scalars.isEmpty else { throw CommandError.invalid("--text has no characters to check.") }
            try needsCoverage(context)
            tests.append { family in
                guard let coverage = context.faceCoverage(family.regular.face) else { return false }
                return coverage.scalars.missingCount(sorted: scalars) <= missing
            }
        }
        if let id = options.set {
            try needsCoverage(context)
            let set = try characterSet(id, in: context)
            tests.append { family in (context.missingCount(set, family.regular.face) ?? .max) <= missing }
        }
        if let tag = options.tag {
            tests.append(filters.filter(for: .tag(try Names.tag(tag, in: context.data))))
        }
        if let folder = options.folder {
            tests.append(filters.filter(for: .set(try Names.folder(folder, in: context.data).id)))
        }
        if let location = options.location {
            tests.append(filters.filter(for: .folder(try Names.location(location, in: context.data).id)))
        }
        if options.active, options.inactive { throw CommandError.invalid("Use --active or --inactive, not both.") }
        if options.active { tests.append(filters.filter(for: .active)) }
        if options.inactive { tests.append(filters.filter(for: .inactive)) }
        return tests
    }

    static func needsCoverage(_ context: LibraryContext) throws {
        guard context.coverage != nil, context.characterSets != nil else {
            throw CommandError(.failed, "Cicero’s character data can’t be found. Run cicero from Cicero.app, or set CICERO_RESOURCES.")
        }
    }

    /// A built-in or custom set by its id.
    static func characterSet(_ id: String, in context: LibraryContext) throws -> CharacterSetDefinition {
        if let set = context.characterSet(id) { return set }
        let byName = context.allSets.filter { Names.fold($0.name) == Names.fold(id) }
        if byName.count == 1 { return byName[0] }
        throw CommandError(.notFound, "No coverage set has the id “\(id)”. See cicero list coverage.",
                           suggestions: Names.suggestions(for: id, among: context.allSets.map(\.id)))
    }

    /// The name among `names` that's `typed`, ignoring case.
    static func exact(_ typed: String, among names: Set<String>, kind: String) throws -> String {
        if names.contains(typed) { return typed }
        let found = names.filter { Names.fold($0) == Names.fold(typed) }
        if found.count == 1 { return found.first! }
        throw CommandError(.notFound, "No \(kind) is called “\(typed)”.", suggestions: Names.suggestions(for: typed, among: names.sorted()))
    }

    // MARK: Ranges

    /// "2019", "2015..2020", "2015..", "..2020".
    static func years(_ text: String) throws -> ClosedRange<Int> {
        let (low, high) = try bounds(text, name: "--released")
        func year(_ part: String?, _ fallback: Int) throws -> Int {
            guard let part else { return fallback }
            guard let year = Int(part), part.count == 4 else { throw CommandError.invalid("--released takes years, like 2019 or 2015..2020.") }
            return year
        }
        let range = (try year(low, Int.min), try year(high, Int.max))
        guard range.0 <= range.1 else { throw CommandError.invalid("--released: the first year comes after the second.") }
        return range.0...range.1
    }

    /// "2024", "2024-03", "2024-03-15", or a range of them: from the start of the first, in the Mac's time zone, to the
    /// end of the second.
    static func dates(_ text: String) throws -> Range<Date> {
        let (low, high) = try bounds(text, name: "--added")
        let calendar = Calendar.current
        func period(_ part: String) throws -> DateInterval {
            let numbers = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
            guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }), part.split(separator: "-")[0].count == 4 else {
                throw CommandError.invalid("--added takes dates, like 2024, 2024-03 or 2024-03-15, or a range like 2024-03..")
            }
            var components = DateComponents(year: numbers[0]!, month: numbers.count > 1 ? numbers[1]! : 1, day: numbers.count > 2 ? numbers[2]! : 1)
            components.calendar = calendar
            guard components.isValidDate(in: calendar), let start = calendar.date(from: components) else {
                throw CommandError.invalid("--added: \(part) isn’t a date.")
            }
            let unit: Calendar.Component = numbers.count == 1 ? .year : numbers.count == 2 ? .month : .day
            return calendar.dateInterval(of: unit, for: start) ?? DateInterval(start: start, duration: 86_400)
        }
        let start = try low.map { try period($0).start } ?? .distantPast
        let end = try high.map { try period($0).end } ?? .distantFuture
        guard start < end else { throw CommandError.invalid("--added: the first date comes after the second.") }
        return start..<end
    }

    /// The two ends of "a..b", "a..", "..b", or "a" for both.
    static func bounds(_ text: String, name: String) throws -> (String?, String?) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let range = text.range(of: "..") else {
            guard !text.isEmpty else { throw CommandError.invalid("\(name) needs a value.") }
            return (text, text)
        }
        let low = String(text[..<range.lowerBound]), high = String(text[range.upperBound...])
        guard !low.isEmpty || !high.isEmpty else { throw CommandError.invalid("\(name) needs at least one end of the range.") }
        return (low.isEmpty ? nil : low, high.isEmpty ? nil : high)
    }
}
