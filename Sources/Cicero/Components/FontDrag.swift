import CoreTransferable
import UniformTypeIdentifiers

/// A family, or one style of it, being dragged onto the sidebar. The browser's grid and lists drag plain family names,
/// which come in as whole families; a font page's style rows drag one style, which a set takes on its own.
nonisolated struct FontDrag: Codable, Transferable {
    var family: String
    /// The style's PostScript name; none for the whole family.
    var style: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciceroFontStyle)
        // Elsewhere, like the Compare window, it's the family's name.
        ProxyRepresentation(exporting: \.family, importing: { FontDrag(family: $0) })
    }
}

extension UTType {
    /// Declared in Info.plist.
    nonisolated static let ciceroFontStyle = UTType(exportedAs: "com.maximilianinzinger.cicero.font-style")
}
