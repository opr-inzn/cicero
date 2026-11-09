import Foundation

public struct FontMatcher: Sendable {
    private var byPath: [String: [(family: Family, face: LibraryFace)]] = [:]
    private var byPostScriptName: [String: (family: Family, face: LibraryFace)] = [:]
    private var byName: [String: (family: Family, face: LibraryFace)] = [:]
    private var byFamily: [String: Family] = [:]

    public init(_ library: Library) {
        for family in library.families {
            let familyKey = Self.key(family.id)
            if byFamily[familyKey] == nil { byFamily[familyKey] = family }
            for face in family.faces {
                for path in [face.face.path] + face.otherCopies { byPath[path, default: []].append((family, face)) }
                let postScriptName = face.face.postScriptName.lowercased()
                if byPostScriptName[postScriptName] == nil { byPostScriptName[postScriptName] = (family, face) }
                let name = familyKey + "|" + Self.key(face.face.styleName)
                if byName[name] == nil { byName[name] = (family, face) }
            }
        }
    }

    static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    public func faces(_ font: ImportedFont, defaultStyle: String? = nil, wholeFile: Bool = false) -> [(family: Family, face: LibraryFace)] {
        let postScriptName = font.postScriptName?.lowercased()
        let inFile = font.path.flatMap { byPath[$0] }
        if let inFile {
            guard let postScriptName, !wholeFile else { return inFile }
            let named = inFile.filter { $0.face.face.postScriptName.lowercased() == postScriptName }
            if !named.isEmpty { return Array(named.prefix(1)) }
            // Another app may read the name its own way: FontBase has "BONIFACE(19-10-18)" for "BONIFACE19-10-18",
            // "Stanley-Bold" for "StanleyBold".
            let spelled = inFile.filter { Self.letters($0.face.face.postScriptName) == Self.letters(postScriptName) }
            if !spelled.isEmpty { return Array(spelled.prefix(1)) }
        }
        if let postScriptName, let found = byPostScriptName[postScriptName] { return [found] }
        if let family = font.family, let style = font.style ?? defaultStyle, let found = byName[Self.key(family) + "|" + Self.key(style)] {
            return [found]
        }
        // The file, by a name none of its styles has: a variable font's own name for its instances, as FontBase gives it.
        return inFile ?? []
    }

    static func letters(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    public func family(named name: String) -> Family? {
        byFamily[Self.key(name)]
    }
}
