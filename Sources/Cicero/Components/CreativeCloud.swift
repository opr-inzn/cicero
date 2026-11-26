import AppKit
import CiceroCore

enum CreativeCloud {
    static func open() {
        let workspace = NSWorkspace.shared
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.adobe.acc.AdobeCreativeCloud") {
            workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(URL(string: "https://fonts.adobe.com/")!)
        }
    }

    static func open(_ paths: some Sequence<String>) {
        if let page = page(for: paths) { NSWorkspace.shared.open(page) } else { open() }
    }

    static func page(for paths: some Sequence<String>) -> URL? {
        pages.page(forPaths: paths)
    }

    static func page(for family: Family) -> URL? {
        page(for: family.faces.lazy.flatMap { [$0.face.path] + $0.otherCopies })
    }

    private static let list = Locations.standard.adobeFontsList
    private static var read: (modified: Date?, pages: AdobeFontsPages)?
    private static var checked = Date.distantPast

    private static var pages: AdobeFontsPages {
        guard let list else { return AdobeFontsPages() }
        if let read, Date.now.timeIntervalSince(checked) < 1 { return read.pages }
        checked = .now
        let modified = (try? FileManager.default.attributesOfItem(atPath: list.path))?[.modificationDate] as? Date
        if let read, read.modified == modified { return read.pages }
        let pages = modified == nil ? AdobeFontsPages() : AdobeFontsPages(contentsOf: list)
        read = (modified, pages)
        return pages
    }
}
