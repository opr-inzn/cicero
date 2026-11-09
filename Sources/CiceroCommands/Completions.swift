import CiceroCore
import Foundation

public enum CompletionNames {
    public enum Kind: Sendable {
        case families, tags, folders, locations, foundries, classes, coverage
        case styles
    }

    public static func names(_ kind: Kind, words: [String], environment: ToolEnvironment) -> [String] {
        let words = words.map(unquoted)
        guard let saved = try? LibraryContext.loadUserData(environment) else { return [] }
        switch kind {
        case .tags: return saved.tags
        case .folders: return saved.sets.map(\.name)
        case .locations: return saved.namedFolders.map(\.displayName)
        case .classes: return saved.classificationNames
        case .coverage:
            let catalog = environment.resources.map { CharacterSetCatalog(contentsOf: $0.appendingPathComponent("CharacterSets.json")) }
            let custom = saved.customCharacterSets.enumerated().map { CharacterSetCatalog.definition(for: $1, level: $0) }
            return ((catalog?.builtIn ?? []) + custom).map(\.id)
        case .families, .foundries, .styles:
            // Proofing fonts shown other than as Cicero's setting has them need a scan: left as saved.
            let shown = ShownFonts(systemFonts: flag("system-fonts", in: words), adobeFonts: flag("adobe-fonts", in: words))
            let data = shown.applied(to: saved)
            let scanner = LibraryScanner(locations: environment.locations, registrar: environment.registrar, saves: false)
            guard let library = scanner.savedLibraryAsNow(records: data.records)?.library else { return [] }
            let context = LibraryContext(environment: environment, data: data, savedData: saved, library: library, lastScan: nil,
                                         characterSets: nil, coverage: nil, classificationGuess: { _ in nil })
            switch kind {
            case .foundries:
                return Set(context.listedFamilies.compactMap(context.foundryName)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            case .styles:
                // The first word after the command that names a family.
                for word in words.dropFirst(2) where !word.hasPrefix("-") {
                    if let family = try? Names.family(word, in: context) { return family.faces.map(\.face.styleName) }
                }
                return []
            default:
                return context.listedFamilies.map(\.id)
            }
        }
    }

    static func flag(_ name: String, in words: [String]) -> Bool? {
        words.last { $0 == "--\(name)" || $0 == "--no-\(name)" }.map { $0 == "--\(name)" }
    }

    static func unquoted(_ word: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false
        for character in word {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil } else { result.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else {
                result.append(character)
            }
        }
        return result
    }
}
