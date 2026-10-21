import Foundation

/// The pages on Adobe Fonts' website of the fonts Creative Cloud keeps, from the list it keeps of them
/// (`Locations.adobeFontsList`). Each font's file is named after its number there (".139.otf" is font 139), and its
/// entry links to its family's page, where the family is turned on and off. Only ever read: the list is Creative
/// Cloud's, and written over at each sync.
public struct AdobeFontsPages: Sendable, Equatable {
    /// Each font's family page, by its number.
    public var pages: [String: URL]

    public init(pages: [String: URL] = [:]) {
        self.pages = pages
    }

    /// Creative Cloud's list; empty when there's none or it can't be read, as when Creative Cloud writes it differently.
    public init(contentsOf url: URL) {
        self.init(data: (try? Data(contentsOf: url)) ?? Data())
    }

    public init(data: Data) {
        let reader = ListReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        self.init(pages: reader.pages)
    }

    /// The family page of a file from Adobe Fonts, by the number in its name.
    public func page(forPath path: String) -> URL? {
        guard ActiveSource.isAdobeFonts(path), let number = Self.number(ofPath: path) else { return nil }
        return pages[number]
    }

    /// The family page most of the files from Adobe Fonts among these have.
    public func page(forPaths paths: some Sequence<String>) -> URL? {
        var counts: [URL: Int] = [:]
        for path in paths {
            if let page = page(forPath: path) { counts[page, default: 0] += 1 }
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.absoluteString > b.key.absoluteString }?.key
    }

    /// ".139.otf" → "139".
    static func number(ofPath path: String) -> String? {
        var name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if name.hasPrefix(".") { name.removeFirst() }
        return !name.isEmpty && name.allSatisfy(\.isASCII) && name.allSatisfy(\.isNumber) ? name : nil
    }

    /// Pages on Adobe Fonts' own website only, whatever the list says.
    static func isAdobeFontsPage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "fonts.adobe.com"
    }

    /// `<font><id>139</id>…<properties>…<familyURL>https://fonts.adobe.com/fonts/…</familyURL>` for each font.
    private final class ListReader: NSObject, XMLParserDelegate {
        var pages: [String: URL] = [:]
        private var elements: [String] = []
        private var text = ""
        private var number: String?
        private var page: URL?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "font" { (number, page) = (nil, nil) }
            elements.append(name)
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            elements.removeLast()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            switch name {
            case "id" where elements.last == "font":
                number = value
            case "familyURL" where elements.contains("font"):
                page = URL(string: value).flatMap { AdobeFontsPages.isAdobeFontsPage($0) ? $0 : nil }
            case "font":
                if let number, let page { pages[number] = page }
            default:
                break
            }
        }
    }
}
