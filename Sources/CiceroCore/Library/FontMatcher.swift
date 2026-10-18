import Foundation

/// Finds the library's styles that a document or another font manager names: by the file, by PostScript name, or by
/// family and style names, ignoring case, spaces, hyphens and underscores. Where several styles fit, the first one the
/// library lists.
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

    /// "Minion Pro" and "minionpro" alike.
    static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    /// The styles a font is. With a file, the file's: the one with its PostScript name, or all of them when it gives
    /// none or `wholeFile` asks for all, as for a set that has files rather than styles. Else, or when the file has no
    /// such style, the one with its PostScript name, else the one with its family and style names (`defaultStyle` for a
    /// font that names its family alone). Empty when the library has none.
    public func faces(_ font: ImportedFont, defaultStyle: String? = nil, wholeFile: Bool = false) -> [(family: Family, face: LibraryFace)] {
        let postScriptName = font.postScriptName?.lowercased()
        if let path = font.path, let inFile = byPath[path] {
            guard let postScriptName, !wholeFile else { return inFile }
            let named = inFile.filter { $0.face.face.postScriptName.lowercased() == postScriptName }
            if !named.isEmpty { return Array(named.prefix(1)) }
        }
        if let postScriptName, let found = byPostScriptName[postScriptName] { return [found] }
        if let family = font.family, let style = font.style ?? defaultStyle, let found = byName[Self.key(family) + "|" + Self.key(style)] {
            return [found]
        }
        return []
    }

    /// The family with this name.
    public func family(named name: String) -> Family? {
        byFamily[Self.key(name)]
    }
}
