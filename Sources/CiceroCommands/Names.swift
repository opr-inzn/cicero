import CiceroCore
import Foundation

/// Finding a family, style, tag, folder or location by the name the user typed. An exact name, ignoring case, is the
/// thing; else the command stops with up to five near names: first those the app's search would suggest, then those a
/// few typing mistakes away (see `Names.distance`). Write commands never guess.
public enum Names {
    /// How many near names a `notFound` lists.
    public static let suggestionCount = 5

    /// The family by its name, as the fonts give it (its `id`) or as shown in the Mac's language, ignoring case.
    public static func family(_ typed: String, in context: LibraryContext) throws -> Family {
        let families = context.listedFamilies
        let key = fold(typed)
        let found = families.filter { fold($0.id) == key || fold($0.name) == key }
        if found.count == 1 { return found[0] }
        if found.count > 1 {
            // Families shown under one name: the one whose own name it is, as typed, else ignoring case.
            if let own = found.first(where: { $0.id == typed }) { return own }
            let own = found.filter { fold($0.id) == key }
            if own.count == 1 { return own[0] }
            throw CommandError(.ambiguous, "“\(typed)” is the name of more than one family. Use one of these names.",
                               suggestions: found.map(\.id))
        }
        if let hidden = context.library.families.first(where: { fold($0.id) == key || fold($0.name) == key }) {
            let (why, flag) = hidden.state == .system ? ("comes with macOS", "--system-fonts") : ("is from Adobe Fonts", "--adobe-fonts")
            throw CommandError(.notFound, "\(hidden.id) \(why), and Cicero is set to hide those fonts. Add \(flag) to see it here.")
        }
        throw CommandError(.notFound, "No family is called “\(typed)”.", suggestions: suggestions(for: typed, among: families.flatMap { family in
            family.name == family.id ? [family.id] : [family.id, family.name]
        }))
    }

    /// A style of the family by its style name ("Bold Italic") or PostScript name ("Inter-BoldItalic"), ignoring case.
    public static func style(_ typed: String, of family: Family) throws -> LibraryFace {
        let key = fold(typed)
        let found = family.faces.filter { fold($0.face.styleName) == key || fold($0.face.postScriptName) == key }
        if found.count == 1 { return found[0] }
        if found.count > 1 {
            throw CommandError(.ambiguous, "More than one style of \(family.id) is called “\(typed)”. Use its PostScript name.",
                               suggestions: found.map(\.face.postScriptName))
        }
        throw CommandError(.notFound, "\(family.id) has no style called “\(typed)”.",
                           suggestions: suggestions(for: typed, among: family.faces.flatMap { [$0.face.styleName, $0.face.postScriptName] }))
    }

    /// The tag of that name, ignoring case.
    public static func tag(_ typed: String, in data: UserData) throws -> String {
        let key = fold(typed)
        let found = data.tags.filter { fold($0) == key }
        if let exact = found.first(where: { $0 == typed }) { return exact }
        if found.count == 1 { return found[0] }
        if found.count > 1 { throw CommandError(.ambiguous, "More than one tag is called “\(typed)”.", suggestions: found) }
        throw CommandError(.notFound, "No tag is called “\(typed)”.", suggestions: suggestions(for: typed, among: data.tags))
    }

    /// The folder (a plain folder of the app, `sets` in the data) by its name, ignoring case, or its id.
    public static func folder(_ typed: String, in data: UserData) throws -> FontSet {
        if let id = UUID(uuidString: typed), let set = data.sets.first(where: { $0.id == id }) { return set }
        let key = fold(typed)
        let found = data.sets.filter { fold($0.name) == key }
        if found.count == 1 { return found[0] }
        if found.count > 1 {
            throw CommandError(.ambiguous, "More than one folder is called “\(typed)”. Use its id.",
                               suggestions: found.map { $0.id.uuidString })
        }
        throw CommandError(.notFound, "No folder is called “\(typed)”.", suggestions: suggestions(for: typed, among: data.sets.map(\.name)))
    }

    /// The location (a watched folder) by its name as shown, its path, or its id.
    public static func location(_ typed: String, in data: UserData) throws -> WatchedFolder {
        let folders = data.namedFolders
        if let id = UUID(uuidString: typed), let folder = folders.first(where: { $0.id == id }) { return folder }
        let path = URL(fileURLWithPath: (typed as NSString).expandingTildeInPath).standardizedFileURL.path
        if typed.contains("/"), let folder = folders.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }) {
            return folder
        }
        let key = fold(typed)
        let found = folders.filter { fold($0.displayName) == key }
        if found.count == 1 { return found[0] }
        if found.count > 1 {
            throw CommandError(.ambiguous, "More than one location is called “\(typed)”. Use its path.", suggestions: found.map(\.path))
        }
        throw CommandError(.notFound, "No location is called “\(typed)”.", suggestions: suggestions(for: typed, among: folders.map(\.displayName)))
    }

    // MARK: Near names

    /// Up to `suggestionCount` of the names: first those the app's search field would suggest for what's typed (names
    /// that begin with it, then those with a word that does), then those the fewest typing mistakes away, and no more than
    /// a third of the typed letters, at least 2.
    public static func suggestions(for typed: String, among names: [String]) -> [String] {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let query = SearchQuery(typed)
        var ranked: [(name: String, rank: Int, distance: Int)] = []
        let key = fold(typed)
        let limit = max(2, key.count / 3)
        for name in unique {
            let folded = fold(name)
            if let rank = query.suggestionRank(of: name.lowercased()) ?? query.suggestionRank(of: folded) {
                ranked.append((name, rank, 0))
                continue
            }
            let distance = distance(key, folded, limit: limit)
            if distance <= limit { ranked.append((name, 2, distance)) }
        }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.distance != b.distance { return a.distance < b.distance }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        // A family's own name and the one it shows can both match: one of them is enough.
        return Array(ranked.prefix(suggestionCount).map(\.name))
    }

    /// Lowercased, without accents, for comparing names.
    public static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Damerau–Levenshtein distance (optimal string alignment): insertions, deletions, changes and two letters swapped
    /// each count 1. Stops early, with `limit + 1`, when the names are further apart than `limit`.
    public static func distance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit &+ 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var before = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var smallest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { value = min(value, before[j - 2] + 1) }
                current[j] = value
                smallest = min(smallest, value)
            }
            if smallest > limit { return limit &+ 1 }
            (before, previous, current) = (previous, current, before)
        }
        return previous[b.count]
    }
}
