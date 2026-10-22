import AppKit
import CiceroCore
import UniformTypeIdentifiers

/// The families of a document's fonts that the library has, in the order the Fonts in Document sheet lists them, for the
/// browser to show (Show in Library).
struct DocumentList: Equatable {
    let name: String
    let families: [String]
}

/// The fonts a document uses, for the Fonts in Document sheet, which shows them against the library.
struct DocumentFontsReport: Identifiable {
    let id = UUID()
    let url: URL
    let fonts: [DocumentFont]

    var name: String { url.lastPathComponent }
    /// What a set made from it is called: the file's name without its extension.
    var setName: String { url.deletingPathExtension().lastPathComponent }
}

extension AppModel {
    /// File → Find Fonts in Document…
    func presentFindFontsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = DocumentFonts.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Find Fonts"
        panel.message = "Choose a PDF, IDML, InDesign, Illustrator or Photoshop file to see which fonts it uses."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        findFonts(in: url)
    }

    /// Reads which fonts the document uses, off the main thread, and shows them.
    func findFonts(in url: URL) {
        Task {
            let read = await Task.detached(priority: .userInitiated) { Result { try DocumentFonts.read(url) } }.value
            switch read {
            case .success(let fonts) where fonts.isEmpty:
                showToast("“\(url.lastPathComponent)” doesn’t name any fonts")
            case .success(let fonts):
                documentFonts = DocumentFontsReport(url: url, fonts: fonts)
            case .failure:
                showToast("Couldn’t read the fonts in “\(url.lastPathComponent)”")
            }
        }
    }

    /// The families of the document's fonts that the library has, each once.
    func libraryFamilies(of report: DocumentFontsReport) -> [String] {
        var seen = Set<String>()
        return documentMatches(report).compactMap(\.family).filter { seen.insert($0).inserted }
    }

    /// Fills the browser with the families the document uses that the library has, as Show Similar Fonts does: the
    /// sidebar shows nothing selected, and selecting an item there, or Done in the bar above them, goes back.
    func showInLibrary(_ report: DocumentFontsReport) {
        if similarFamilyID == nil, documentList == nil {
            listReturn = selectedItems
            listReturnPage = openFamilyID
        }
        clearSearch()
        selection = nil
        similarFamilyID = nil
        documentList = DocumentList(name: report.name, families: libraryFamilies(of: report))
        openFamilyID = nil
        selectedIDs = []
    }

    /// Done in the bar above Show in Library's families.
    func endDocumentList() {
        guard documentList != nil else { return }
        returnFromList()
    }

    /// The fonts an app says its document uses, as InDesign does for Find Fonts in Current Document in the menu bar.
    func showFonts(_ fonts: [DocumentFont], ofDocumentNamed name: String) {
        guard !fonts.isEmpty else { return showToast("“\(name)” doesn’t name any fonts") }
        documentFonts = DocumentFontsReport(url: URL(fileURLWithPath: name), fonts: fonts)
    }

    /// The library's face for each of the document's fonts. Cached until the library changes: the sheet asks on
    /// every update, and matching looks at every face.
    func documentMatches(_ report: DocumentFontsReport) -> [DocumentFontMatch] {
        if let cached = documentMatchesCache, cached.report == report.id, cached.fingerprint == library.fingerprint {
            return cached.matches
        }
        let matches = DocumentFonts.match(report.fonts, in: library)
        documentMatchesCache = (report.id, library.fingerprint, matches)
        return matches
    }

    /// A set named after the document with the families of its fonts that are in the library; a set with that
    /// name already gets them added. Returns what to say about it.
    func makeSet(for report: DocumentFontsReport) -> String {
        var seen = Set<String>()
        let families = documentMatches(report).compactMap(\.family).filter { seen.insert($0).inserted }.compactMap(family)
        guard !families.isEmpty else { return "None of its fonts are in your library." }
        let count = families.count == 1 ? "1 family" : "\(families.count) families"
        if let existing = data.sets.first(where: { $0.name == report.setName }) {
            setMembership(true, for: families, in: existing.id)
            return "Added \(count) to the folder “\(report.setName)”."
        }
        addSet(named: report.setName, with: families)
        return "Made the folder “\(report.setName)” with \(count)."
    }

    /// Turns on every font of the document that's in the library and off.
    func activateAll(in report: DocumentFontsReport) {
        let faces = documentMatches(report).compactMap(\.face).filter(\.canActivate)
        guard !faces.isEmpty else { return }
        activate(faces, title: "the Fonts in “\(report.name)”")
    }
}
