import ArgumentParser
import CiceroCommands
import CiceroCore

extension CompletionKind {
    static func names(_ kind: CompletionNames.Kind) -> CompletionKind {
        .custom { words, _, _ in
            let names = CompletionNames.names(kind, words: words, environment: .current())
            // zsh reads each name as name:description, so a colon in a name is escaped there only: fish would show the backslash.
            guard CompletionShell.requesting == .zsh else { return names }
            return names.map { $0.replacingOccurrences(of: ":", with: "\\:") }
        }
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
