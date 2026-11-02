import CiceroCore
import Foundation

/// The names the shell offers when the user presses Tab after a command that takes one: families, tags, folders and so
/// on, as the commands look them up. Read from what Cicero saved, like the read commands, but lighter: no coverage,
/// measurements or guessed classes, never a scan, and nothing written. Anything that goes wrong (Cicero hasn't scanned
/// yet, its data can't be read) gives no names, as Tab must never print an error into the line being typed.
public enum CompletionNames {
    public enum Kind: Sendable {
        case families, tags, folders, locations, foundries, classes, coverage
        /// The styles of the family on the command line (`status <family> --style`).
        case styles
    }

    /// `words` is the command line as typed so far, as the shell has it (quotes and backslashes in place); its flags
    /// that show or hide fonts are followed, as the command will follow them.
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

    /// True for `--name`, false for `--no-name`, nil for neither; the last one given wins, as the command has it.
    static func flag(_ name: String, in words: [String]) -> Bool? {
        words.last { $0 == "--\(name)" || $0 == "--no-\(name)" }.map { $0 == "--\(name)" }
    }

    /// A word as the shell would pass it to the command: quotes taken off, backslashes before characters dropped.
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
