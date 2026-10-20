import CoreGraphics
import CoreText
import Foundation

/// A font a document uses, as the document names it.
public struct DocumentFont: Hashable, Sendable {
    /// "MinionPro-Regular", without a PDF subset's "ABCDEF+" prefix.
    public var postScriptName: String?
    /// "Minion Pro", when the document says.
    public var family: String?
    /// "Regular", when the document says.
    public var style: String?
    /// Whether a PDF carries the font itself; nil for documents that never do.
    public var isEmbedded: Bool?

    public init(postScriptName: String? = nil, family: String? = nil, style: String? = nil, isEmbedded: Bool? = nil) {
        self.postScriptName = postScriptName
        self.family = family
        self.style = style
        self.isEmbedded = isEmbedded
    }

    /// The name to show: the family and style when known, else the PostScript name.
    public var displayName: String {
        if let family, let style { return "\(family) \(style)" }
        return family ?? postScriptName ?? "Unnamed font"
    }
}

/// Reads which fonts a document uses, without opening it in the app that made it and without anything
/// leaving the Mac: PDFs (and Illustrator files, which are PDFs inside) from their pages' font resources,
/// IDML from its font list, InDesign and Illustrator files from the font list in their XMP metadata, and Photoshop
/// files from their text layers.
/// Every reader trusts nothing in the file: what it can't read, it leaves out.
public enum DocumentFonts {
    public enum Failure: Error, Equatable {
        case unreadable
        case unsupported
    }

    public static let fileExtensions: Set<String> = ["pdf", "ai", "idml", "indd", "indt", "psd", "psb"]

    /// The fonts the document uses, each once, in the order found. Reads the file; call off the main thread.
    public static func read(_ url: URL) throws -> [DocumentFont] {
        let fonts: [DocumentFont]
        switch url.pathExtension.lowercased() {
        case "pdf":
            fonts = try pdf(url)
        case "ai":
            // An Illustrator file saved with PDF compatibility is a PDF; its XMP lists the fonts either way.
            fonts = ((try? pdf(url)) ?? []) + xmp(try data(url))
        case "idml":
            fonts = try idml(url)
        case "indd", "indt":
            fonts = xmp(try data(url))
        case "psd", "psb":
            fonts = try photoshop(try data(url))
        default:
            throw Failure.unsupported
        }
        return unique(fonts)
    }

    private static func data(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw Failure.unreadable }
        return data
    }

    /// Each font once, by PostScript name or else family and style; what one entry knows fills the other's gaps.
    static func unique(_ fonts: [DocumentFont]) -> [DocumentFont] {
        var result: [DocumentFont] = []
        var index: [String: Int] = [:]
        for font in fonts {
            let key = (font.postScriptName ?? "\(font.family ?? "")|\(font.style ?? "")").lowercased()
            guard key != "|" else { continue }
            if let at = index[key] {
                result[at].family = result[at].family ?? font.family
                result[at].style = result[at].style ?? font.style
                if font.isEmbedded == true { result[at].isEmbedded = true }
            } else {
                index[key] = result.count
                result.append(font)
            }
        }
        return result
    }

    // MARK: PDF

    /// The fonts in every page's resources, and in the form XObjects and annotation appearances they use.
    static func pdf(_ url: URL) throws -> [DocumentFont] {
        guard let document = CGPDFDocument(url as CFURL) else { throw Failure.unreadable }
        guard !document.isEncrypted || document.unlockWithPassword("") else { throw Failure.unreadable }
        var collector = PDFFontCollector()
        for number in stride(from: 1, through: document.numberOfPages, by: 1) {
            guard let page = document.page(at: number)?.dictionary else { continue }
            collector.resources(of: page)
            var annotations: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(page, "Annots", &annotations), let annotations {
                for index in 0..<CGPDFArrayGetCount(annotations) {
                    var annotation: CGPDFDictionaryRef?
                    var appearances: CGPDFDictionaryRef?
                    guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
                          CGPDFDictionaryGetDictionary(annotation, "AP", &appearances), let appearances
                    else { continue }
                    var normal: CGPDFStreamRef?
                    if CGPDFDictionaryGetStream(appearances, "N", &normal), let normal, let dictionary = CGPDFStreamGetDictionary(normal) {
                        collector.resources(of: dictionary)
                    }
                }
            }
        }
        return collector.fonts
    }

    /// "ABCDEF+MinionPro-Regular" → "MinionPro-Regular": a subset's tag is six capitals and a plus.
    static func withoutSubsetTag(_ name: String) -> String {
        let parts = name.split(separator: "+", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 6, parts[0].allSatisfy({ $0.isASCII && $0.isUppercase }) else { return name }
        return String(parts[1])
    }

    // MARK: IDML

    /// The fonts an IDML package uses. Its Resources/Fonts.xml lists every style of each family the document
    /// uses, so that list is narrowed to the families and styles its styles and stories apply. Read with unzip
    /// to standard output, so nothing in the archive is written anywhere.
    static func idml(_ url: URL) throws -> [DocumentFont] {
        let fonts = try unzip(url, ["Resources/Fonts.xml"])
        guard !fonts.isEmpty else { throw Failure.unreadable }
        let applied = (try? unzip(url, ["Resources/Styles.xml", "Stories/*.xml", "Spreads/*.xml", "MasterSpreads/*.xml"])) ?? Data()
        return idmlFonts(fonts, applying: applied)
    }

    private static func unzip(_ url: URL, _ members: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path] + members
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.unreadable }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 11: some of the members aren't there, as a package without master spreads.
        guard process.terminationStatus == 0 || process.terminationStatus == 11 else { throw Failure.unreadable }
        return data
    }

    /// `<Font FontFamily="Minion Pro" PostScriptName="MinionPro-Regular" FontStyleName="Regular" …/>` for the
    /// families and styles applied in `applied` (the package's styles and stories, one after the other): its
    /// `<AppliedFont type="string">Minion Pro</AppliedFont>` and `FontStyle="Regular"`. Without any, all of them.
    static func idmlFonts(_ fonts: Data, applying applied: Data) -> [DocumentFont] {
        let reader = ElementReader(names: ["Font"])
        reader.parse(fonts)
        let listed = reader.elements.compactMap { attributes -> DocumentFont? in
            let font = DocumentFont(
                postScriptName: attributes["PostScriptName"].flatMap(nonEmpty),
                family: attributes["FontFamily"].flatMap(nonEmpty),
                style: attributes["FontStyleName"].flatMap(nonEmpty)
            )
            return font.postScriptName == nil && font.family == nil ? nil : font
        }
        let text = String(decoding: applied, as: UTF8.self)
        let families = Set(text.matches(of: #/<AppliedFont type="string">([^<]*)</AppliedFont>/#).map { unescaped(String($0.1)) })
        let styles = Set(text.matches(of: #/ FontStyle="([^"]*)"/#).map { unescaped(String($0.1)) })
        guard !families.isEmpty else { return listed }
        return listed.filter { font in
            guard let family = font.family, families.contains(family) else { return false }
            return styles.isEmpty || font.style.map(styles.contains) ?? true
        }
    }

    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: XMP

    /// The fonts in an XMP packet's xmpTPg:Fonts list (InDesign and Illustrator write one), from the first
    /// packet that has them. An InDesign file can hold others, from placed images, which don't.
    static func xmp(_ data: Data) -> [DocumentFont] {
        let start = Data("<x:xmpmeta".utf8), end = Data("</x:xmpmeta>".utf8)
        var from = data.startIndex
        while let open = data.range(of: start, in: from..<data.endIndex),
              let close = data.range(of: end, in: open.upperBound..<data.endIndex) {
            let packet = data[open.lowerBound..<close.upperBound]
            from = close.upperBound
            guard packet.range(of: Data("xmpTPg:Fonts".utf8)) != nil else { continue }
            let fonts = xmpFonts(Data(packet))
            if !fonts.isEmpty { return fonts }
        }
        return []
    }

    /// Each rdf:li of xmpTPg:Fonts with its stFnt: fields, written as attributes or as elements.
    static func xmpFonts(_ packet: Data) -> [DocumentFont] {
        let reader = XMPFontReader()
        reader.parse(packet)
        return reader.fonts.compactMap { fields in
            let font = DocumentFont(
                postScriptName: fields["fontName"].flatMap(nonEmpty),
                family: fields["fontFamily"].flatMap(nonEmpty),
                style: fields["fontFace"].flatMap(nonEmpty)
            )
            return font.postScriptName == nil && font.family == nil ? nil : font
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Readers

/// Walks PDF resource dictionaries for fonts, each dictionary once (pages share them, forms nest).
private struct PDFFontCollector {
    var fonts: [DocumentFont] = []
    /// The resource dictionaries walked, by address.
    private var seen = Set<Int>()

    /// A page's, form's or appearance's Resources: its fonts, then its form XObjects' own resources.
    mutating func resources(of owner: CGPDFDictionaryRef) {
        var found: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(owner, "Resources", &found), let resources = found,
              seen.insert(unsafeBitCast(resources, to: Int.self)).inserted, seen.count < 10_000
        else { return }
        var fontDictionary: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fontDictionary), let fontDictionary {
            var entries: [DocumentFont] = []
            CGPDFDictionaryApplyBlock(fontDictionary, { _, object, _ in
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(object, .dictionary, &font), let font, let entry = Self.font(font) { entries.append(entry) }
                return true
            }, nil)
            fonts += entries
        }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return }
        var forms: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            var subtype: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream),
               CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Form" {
                forms.append(dictionary)
            }
            return true
        }, nil)
        for form in forms { self.resources(of: form) }
    }

    /// A font dictionary's BaseFont, and whether its descriptor (a composite font's descendant's) has a font file.
    private static func font(_ font: CGPDFDictionaryRef) -> DocumentFont? {
        var name: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(font, "BaseFont", &name), let name else { return nil }  // Type 3 fonts have none
        var base = DocumentFonts.withoutSubsetTag(String(cString: name))
        var descriptorOwner = font
        var descendants: CGPDFArrayRef?
        var descendant: CGPDFDictionaryRef?
        if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
           CGPDFArrayGetDictionary(descendants, 0, &descendant), let descendant {
            descriptorOwner = descendant
            // A composite font's name may end in its encoding: "MinionPro-Regular-Identity-H".
            for suffix in ["-Identity-H", "-Identity-V"] where base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)) }
        }
        var descriptor: CGPDFDictionaryRef?
        var embedded = false
        if CGPDFDictionaryGetDictionary(descriptorOwner, "FontDescriptor", &descriptor), let descriptor {
            var file: CGPDFStreamRef?
            for key in ["FontFile", "FontFile2", "FontFile3"] where CGPDFDictionaryGetStream(descriptor, key, &file) { embedded = true }
        }
        // "Arial,Bold", as some apps name fonts they don't embed: a family and a style.
        let parts = base.split(separator: ",", maxSplits: 1).map(String.init)
        if parts.count == 2 { return DocumentFont(postScriptName: base, family: parts[0], style: parts[1], isEmbedded: embedded) }
        return DocumentFont(postScriptName: base, isEmbedded: embedded)
    }
}

/// Collects the attributes of elements with some names.
private final class ElementReader: NSObject, XMLParserDelegate {
    let names: Set<String>
    var elements: [[String: String]] = []

    init(names: Set<String>) {
        self.names = names
    }

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if names.contains(name) { elements.append(attributes) }
    }
}

/// The stFnt: fields of each font in an XMP packet's xmpTPg:Fonts bag.
private final class XMPFontReader: NSObject, XMLParserDelegate {
    var fonts: [[String: String]] = []
    private var inFonts = false
    private var current: [String: String]?
    private var field: String?
    private var text = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        parser.parse()
    }

    private static func field(_ name: String) -> String? {
        name.hasPrefix("stFnt:") ? String(name.dropFirst("stFnt:".count)) : nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "xmpTPg:Fonts" { inFonts = true }
        guard inFonts else { return }
        if name == "rdf:li" {
            current = [:]
            for (key, value) in attributes { if let field = Self.field(key) { current?[field] = value } }
        } else if current != nil, let field = Self.field(name) {
            self.field = field
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if let field, Self.field(name) == field {
            current?[field] = text
            self.field = nil
        } else if name == "rdf:li", let font = current {
            fonts.append(font)
            current = nil
        } else if name == "xmpTPg:Fonts" {
            inFonts = false
        }
    }
}

// MARK: - Matching

/// A font a document uses, and the face in the library that is it, if there's one.
public struct DocumentFontMatch: Sendable, Identifiable {
    public let font: DocumentFont
    public let family: String?
    public let face: LibraryFace?
    /// Apps have the font: its face in the library is on, or macOS has it under that PostScript name though
    /// the library doesn't list it (some fonts that come with macOS, like Times).
    public let isInstalled: Bool

    public var id: String { font.postScriptName ?? font.displayName }
}

extension DocumentFonts {
    /// The library's face for each font: the one with its PostScript name, else the one whose family and style
    /// names are the document's (ignoring case and spaces), else none.
    public static func match(_ fonts: [DocumentFont], in library: Library) -> [DocumentFontMatch] {
        let matcher = FontMatcher(library)
        return fonts.map { font in
            let named = ImportedFont(postScriptName: font.postScriptName, family: font.family, style: font.style)
            let found = matcher.faces(named, defaultStyle: "Regular").first
            let installed = found?.face.state.isActive ?? font.postScriptName.map(isInstalled) ?? false
            return DocumentFontMatch(font: font, family: found?.family.id, face: found?.face, isInstalled: installed)
        }
    }

    /// Whether macOS has a font with exactly this PostScript name; asking for one it hasn't gives a stand-in.
    static func isInstalled(_ postScriptName: String) -> Bool {
        CTFontCopyPostScriptName(CTFontCreateWithName(postScriptName as CFString, 12, nil)) as String == postScriptName
    }
}
