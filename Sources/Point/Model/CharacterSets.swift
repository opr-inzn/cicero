import Foundation

/// A list of characters a font should have, like Latin S or Adobe Latin 3. Built-in sets come
/// from `CharacterSets.json` (see scripts/update-character-sets.py); people can add their own.
struct CharacterSetDefinition: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var summary: String
    var groupID: String
    /// Position within the group; larger sets in a series come later.
    var level: Int
    /// Sorted, unique.
    var scalars: [UInt32]

    var isCustom: Bool { groupID == CharacterSetGroup.customID }

    var sampleText: String {
        String(String.UnicodeScalarView(scalars.prefix(400).compactMap(Unicode.Scalar.init)))
    }
}

struct CharacterSetGroup: Identifiable, Sendable {
    static let customID = "custom"

    var id: String
    var name: String
    var credit: String
    var url: String
    var sets: [CharacterSetDefinition]
}

/// A character set someone defined themselves.
struct CustomCharacterSet: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    /// What they typed or pasted: characters, U+ codes or ranges.
    var characters: String

    var definitionID: String { "custom.\(id.uuidString)" }

    func definition(level: Int) -> CharacterSetDefinition {
        CharacterSetDefinition(
            id: definitionID, name: name, summary: "", groupID: CharacterSetGroup.customID,
            level: level, scalars: CharacterSetCatalog.parse(characters)
        )
    }
}

enum CharacterSetCatalog {
    static let groups: [CharacterSetGroup] = load()
    static let builtIn: [CharacterSetDefinition] = groups.flatMap(\.sets)
    static let defaultShownIDs: Set<String> = ["latin-s", "latin-m", "latin-l", "latin-xl"]
    /// Groups whose sets each contain the previous one, so "the largest one a font has" makes sense.
    static let seriesIDs: Set<String> = ["koeberlin", "adobe"]

    private static func load() -> [CharacterSetGroup] {
        guard let url = Bundle.main.url(forResource: "CharacterSets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.groups.map { group in
            CharacterSetGroup(
                id: group.id, name: group.name, credit: group.credit, url: group.url,
                sets: group.sets.enumerated().map { level, set in
                    CharacterSetDefinition(
                        id: set.id, name: set.name, summary: set.summary, groupID: group.id,
                        level: level, scalars: Array(Set(set.scalars)).sorted()
                    )
                }
            )
        }
    }

    private struct File: Decodable {
        struct Group: Decodable {
            var id, name, credit, url: String
            var sets: [Entry]
        }
        struct Entry: Decodable {
            var id, name, summary: String
            var scalars: [UInt32]
        }
        var groups: [Group]
    }

    /// Reads characters typed or pasted by hand. Understands `U+00C1`, `0x00C1`, ranges like
    /// `U+0100–U+017F` or `U+0100-017F`, and plain characters. Whitespace is ignored.
    static func parse(_ text: String) -> [UInt32] {
        var result = Set<UInt32>()
        let code = #"(?:[Uu]\+|0[xX])([0-9A-Fa-f]{2,6})"#
        let pattern = try! NSRegularExpression(pattern: code + #"(?:\s*[-–—]\s*(?:(?:[Uu]\+|0[xX])?([0-9A-Fa-f]{2,6})))?"#)
        let ns = text as NSString
        var plain = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            plain += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            guard let low = UInt32(ns.substring(with: match.range(at: 1)), radix: 16) else { continue }
            var high = low
            if match.range(at: 2).location != NSNotFound, let end = UInt32(ns.substring(with: match.range(at: 2)), radix: 16) {
                high = end
            }
            guard low <= high, high - low <= 0x10000 else { continue }
            for value in low...high where Unicode.Scalar(value) != nil { result.insert(value) }
        }
        plain += ns.substring(from: cursor)
        result.formUnion(CharacterCoverage.scalars(in: plain))
        return result.sorted()
    }
}

extension ScalarRanges {
    /// How many of the sorted scalars the face lacks, walking both lists once.
    func missingCount(sorted scalars: [UInt32]) -> Int {
        var missing = 0
        var range = 0
        let rangeCount = bounds.count / 2
        for scalar in scalars {
            while range < rangeCount && bounds[range * 2 + 1] < scalar { range += 1 }
            if range == rangeCount || bounds[range * 2] > scalar { missing += 1 }
        }
        return missing
    }
}

/// Remembers which families have which character sets, for the current coverage data.
@MainActor
final class CharacterSetIndex {
    private var generation = -1
    private var missing: [String: Int] = [:]

    /// Characters of the set the family lacks; nil while the family's coverage is still being worked out.
    func missingCount(_ family: FontFamily, _ set: CharacterSetDefinition) -> Int? {
        let coverage = CharacterCoverage.shared
        if coverage.generation != generation {
            generation = coverage.generation
            missing.removeAll(keepingCapacity: true)
        }
        let face = CharacterCoverage.representative(of: family)
        let key = "\(set.id)|\(set.scalars.count)|\(face.id)"
        if let known = missing[key] { return known }
        guard let ranges = coverage.coverage(of: face)?.scalars else { return nil }
        let count = ranges.missingCount(sorted: set.scalars)
        missing[key] = count
        return count
    }

    func invalidate() {
        missing.removeAll()
    }
}

extension LibraryStore {
    /// Built-in sets followed by the user's own.
    var characterSets: [CharacterSetDefinition] {
        CharacterSetCatalog.builtIn + customCharacterSetDefinitions
    }

    var customCharacterSetDefinitions: [CharacterSetDefinition] {
        data.customCharacterSets.enumerated().map { $1.definition(level: $0) }
    }

    func characterSet(_ id: String) -> CharacterSetDefinition? {
        if id.hasPrefix("custom.") {
            return customCharacterSetDefinitions.first { $0.id == id }
        }
        return CharacterSetCatalog.builtIn.first { $0.id == id }
    }

    /// nil while the family's characters are still being checked.
    func supports(_ family: FontFamily, characterSet set: CharacterSetDefinition) -> Bool? {
        characterSetIndex.missingCount(family, set).map { $0 == 0 }
    }

    /// The largest set of a series the family has, or nil when it has none of them.
    func largestCharacterSet(of family: FontFamily, inGroup groupID: String) -> CharacterSetDefinition? {
        let series = CharacterSetCatalog.groups.first { $0.id == groupID }?.sets ?? []
        return series.reversed().first { supports(family, characterSet: $0) == true }
    }

    // MARK: Custom sets

    func addCharacterSet(named name: String, characters: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let set = CustomCharacterSet(name: trimmed, characters: characters)
        data.customCharacterSets.append(set)
        data.shownCharacterSets.insert(set.definitionID)
        data.hiddenSidebarItems.remove(SidebarSection.characterSets.key)
        save()
    }

    func updateCharacterSet(_ id: UUID, name: String, characters: String) {
        guard let index = data.customCharacterSets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { data.customCharacterSets[index].name = trimmed }
        data.customCharacterSets[index].characters = characters
        characterSetIndex.invalidate()
        save()
    }

    func deleteCharacterSet(_ id: UUID) {
        let key = "custom.\(id.uuidString)"
        data.customCharacterSets.removeAll { $0.id == id }
        data.shownCharacterSets.remove(key)
        for index in data.smartSets.indices {
            data.smartSets[index].rules.removeAll { $0.field == .characterSet && $0.value == key }
        }
        if sidebarSelection == .characterSet(key) { sidebarSelection = .all }
        save()
    }
}
