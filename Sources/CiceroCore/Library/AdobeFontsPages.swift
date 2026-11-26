import Foundation

public struct AdobeFontsPages: Sendable, Equatable {
    public var pages: [String: URL]

    public init(pages: [String: URL] = [:]) {
        self.pages = pages
    }

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

    public func page(forPath path: String) -> URL? {
        guard ActiveSource.isAdobeFonts(path), let number = Self.number(ofPath: path) else { return nil }
        return pages[number]
    }

    public func page(forPaths paths: some Sequence<String>) -> URL? {
        var counts: [URL: Int] = [:]
        for path in paths {
            if let page = page(forPath: path) { counts[page, default: 0] += 1 }
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.absoluteString > b.key.absoluteString }?.key
    }

    static func number(ofPath path: String) -> String? {
        var name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        // Creative Cloud names each font's file after its number on Adobe Fonts, hidden: ".139.otf" is font 139.
        if name.hasPrefix(".") { name.removeFirst() }
        return !name.isEmpty && name.allSatisfy(\.isASCII) && name.allSatisfy(\.isNumber) ? name : nil
    }

    static func isAdobeFontsPage(_ url: URL) -> Bool {
        // Only Adobe Fonts' own website, whatever the list says: the list is another app's file, and the app opens its links.
        url.scheme == "https" && url.host == "fonts.adobe.com"
    }

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
