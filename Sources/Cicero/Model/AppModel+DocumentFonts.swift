import AppKit
import CiceroCore
import UniformTypeIdentifiers

struct DocumentList: Equatable {
    let name: String
    let families: [String]
}

struct DocumentFontsReport: Identifiable {
    let id = UUID()
    let url: URL
    let fonts: [DocumentFont]

    var name: String { url.lastPathComponent }
}

extension AppModel {
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

    func findFonts(in url: URL) {
        Task {
            let read = await Task.detached(priority: .userInitiated) { Result { try DocumentFonts.read(url) } }.value
            switch read {
            case .success(let fonts) where fonts.isEmpty:
                showToast("“\(url.lastPathComponent)” doesn’t name any fonts")
            case .success(let fonts):
                ask { $0.documentFonts = DocumentFontsReport(url: url, fonts: fonts) }
            case .failure:
                showToast("Couldn’t read the fonts in “\(url.lastPathComponent)”")
            }
        }
    }

    func libraryFamilies(of report: DocumentFontsReport) -> [String] {
        var seen = Set<String>()
        return documentMatches(report).compactMap(\.family).filter { seen.insert($0).inserted }
    }

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

    func endDocumentList() {
        guard documentList != nil else { return }
        returnFromList()
    }

    func showFonts(_ fonts: [DocumentFont], ofDocumentNamed name: String) {
        guard !fonts.isEmpty else { return showToast("“\(name)” doesn’t name any fonts") }
        ask { $0.documentFonts = DocumentFontsReport(url: URL(fileURLWithPath: name), fonts: fonts) }
    }

    func documentMatches(_ report: DocumentFontsReport) -> [DocumentFontMatch] {
        if let cached = documentMatchesCache, cached.report == report.id, cached.fingerprint == library.fingerprint {
            return cached.matches
        }
        let matches = DocumentFonts.match(report.fonts, in: library)
        documentMatchesCache = (report.id, library.fingerprint, matches)
        return matches
    }

    func activateAll(in report: DocumentFontsReport) {
        let faces = documentMatches(report).compactMap(\.face).filter(\.canActivate)
        guard !faces.isEmpty else { return }
        activate(faces, title: "the Fonts in “\(report.name)”")
    }
}
