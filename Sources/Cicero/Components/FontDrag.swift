import CoreTransferable
import UniformTypeIdentifiers

/// Families, or one style of one, being dragged onto the sidebar. The browser's grid and lists and the Character Toolbox
/// drag every selected family when the one dragged is selected, else just that one; a font page's style rows drag one
/// style, which a set takes on its own.
nonisolated struct FontDrag: Codable, Transferable {
    var families: [String]
    /// The style's PostScript name, of the one family; none for whole families.
    var style: String?

    init(families: [String]) {
        self.families = families
    }

    init(family: String, style: String) {
        families = [family]
        self.style = style
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroFontStyle)
        // Elsewhere it's the families' names, one per line, and names dropped from elsewhere come in the same way.
        ProxyRepresentation(exporting: { $0.families.joined(separator: "\n") },
                            importing: { FontDrag(families: $0.split(whereSeparator: \.isNewline).map(String.init)) })
    }
}

extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroFontStyle = UTType(exportedAs: "com.maximilianinzinger.cicero.font-style")
}
