import AppKit
import CiceroCore

/// Adobe Fonts are turned on and off in Creative Cloud, or on the family's page on Adobe Fonts' website. Creative
/// Cloud's app takes no links to its Fonts page, so a family's fonts open that page, from Creative Cloud's list of
/// them (see `AdobeFontsPages`), and the app opens without one.
enum CreativeCloud {
    /// Opens the app, or Adobe Fonts' website without it.
    static func open() {
        let workspace = NSWorkspace.shared
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.adobe.acc.AdobeCreativeCloud") {
            workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(URL(string: "https://fonts.adobe.com/")!)
        }
    }

    /// Opens the page of the family these files from Adobe Fonts are from, or the app when there's none.
    static func open(_ paths: some Sequence<String>) {
        if let page = page(for: paths) { NSWorkspace.shared.open(page) } else { open() }
    }

    /// The page on Adobe Fonts' website of the family the files from Adobe Fonts among these are from.
    static func page(for paths: some Sequence<String>) -> URL? {
        pages.page(forPaths: paths)
    }

    /// The family's own page on Adobe Fonts' website, from any of its copies from Adobe Fonts.
    static func page(for family: Family) -> URL? {
        page(for: family.faces.lazy.flatMap { [$0.face.path] + $0.otherCopies })
    }

    private static let list = Locations.standard.adobeFontsList
    private static var read: (modified: Date?, pages: AdobeFontsPages)?
    private static var checked = Date.distantPast

    /// Creative Cloud's list, read again when it has changed: looked at once a second at most, as menus and pages ask
    /// as they're drawn.
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
