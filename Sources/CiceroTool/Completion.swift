import ArgumentParser
import CiceroCommands
import CiceroCore

/// What Tab offers for an argument (see `CompletionNames`). The names come from the tool itself, run by the shell's
/// completion script at each Tab, so they're always the library's names now.
extension CompletionKind {
    static func names(_ kind: CompletionNames.Kind) -> CompletionKind {
        .custom { words, _, _ in
            // zsh reads each name as name:description, so a colon in a name is escaped.
            CompletionNames.names(kind, words: words, environment: .current()).map { $0.replacingOccurrences(of: ":", with: "\\:") }
        }
    }

    static let families = names(.families)
    static let tags = names(.tags)
    static let folders = names(.folders)

    /// The style words of `--filter`, one word each, as its help gives them: "extrabold", "tnum".
    static let styleWords = list(SearchToken.all.map { token in
        switch token {
        case .tabularFigures: "tnum"
        case .oldStyleFigures: "onum"
        default: token.title.lowercased().replacingOccurrences(of: " ", with: "")
        }
    })
    static let colors = list(TagColor.allCases.map(\.rawValue))
}
