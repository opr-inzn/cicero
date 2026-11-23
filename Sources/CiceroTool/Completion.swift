import ArgumentParser
import CiceroCommands
import CiceroCore

extension CompletionKind {
    static func names(_ kind: CompletionNames.Kind) -> CompletionKind {
        .custom { words, _, _ in
            let names = CompletionNames.names(kind, words: words, environment: .current())
                .filter { !$0.unicodeScalars.contains { $0.properties.generalCategory == .control } }
            switch CompletionShell.requesting {
            // zsh reads each name as name:description, so a colon in a name is escaped there only: fish would show the backslash.
            case .zsh: return names.map { $0.replacingOccurrences(of: ":", with: "\\:") }
            // Security: bash expands each word of `compgen -W` ($(…), backticks, quotes) and then puts it on the command line as it is, so a font's name is escaped twice.
            case .bash: return names.map { shellEscaped(shellEscaped($0)) }
            default: return names
            }
        }
    }

    static func shellEscaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if character.isASCII, !(character.isLetter || character.isNumber || "-_.,+@%/".contains(character)) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    static let families = names(.families)
    static let tags = names(.tags)
    static let folders = names(.folders)

    static let styleWords = list(SearchToken.all.map { token in
        switch token {
        case .tabularFigures: "tnum"
        case .oldStyleFigures: "onum"
        default: token.title.lowercased().replacingOccurrences(of: " ", with: "")
        }
    })
    static let colors = list(TagColor.allCases.map(\.rawValue))
}
