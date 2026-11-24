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
    let embedded: [String: PDFEmbeddedFont]

    init(url: URL, fonts: [DocumentFont], embedded: [String: PDFEmbeddedFont] = [:]) {
        self.url = url
        self.fonts = fonts
        self.embedded = embedded
    }

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
            let read = await Task.detached(priority: .userInitiated) {
                Result {
                    let fonts = try DocumentFonts.read(url)
                    let embedded = PDFEmbeddedFont.extractAll(from: url).filter { $0.value.makeFont() != nil }
                    return (fonts, embedded)
                }
            }.value
            switch read {
            case .success(let (fonts, _)) where fonts.isEmpty:
                showToast("“\(url.lastPathComponent)” doesn’t list any fonts")
            case .success(let (fonts, embedded)):
                ask { $0.documentFonts = DocumentFontsReport(url: url, fonts: fonts, embedded: embedded) }
            case .failure:
                showToast("Couldn’t read the fonts in “\(url.lastPathComponent)”")
            }
        }
    }

    func embeddedFont(for font: DocumentFont, in report: DocumentFontsReport) -> PDFEmbeddedFont? {
        guard let key = font.postScriptName?.lowercased() else { return nil }
        return report.embedded[key]
    }

    func showSimilar(to font: DocumentFont, embedded: PDFEmbeddedFont) {
        let index = measurements
        let table = similarFonts
        let data = data
        Task {
            let result: [String]? = await Task.detached(priority: .userInitiated) {
                guard let (ctFont, glyphMap) = embedded.makeFont() else { return nil }
                let (measured, reading) = index.inspect(ctFont, glyphMap: glyphMap)
                var guessedClass: String?
                if let chances = reading?.classification,
                   let best = chances.indices.max(by: { chances[$0] < chances[$1] }),
                   chances[best] >= ClassificationGuesses.letterLikelihood {
                    guessedClass = data.name(of: LetterEmbedding.classifications[best])
                } else if measured?[.monospaced] == 1 {
                    guessedClass = data.name(of: .monospaced)
                }
                return table.nearest(
                    measurements: measured, embedding: reading?.embedding, tags: reading?.tags,
                    classification: guessedClass, name: font.displayName, limit: SimilarFonts.longestList
                )
            }.value
            guard let nearest = result, !nearest.isEmpty else {
                showToast("Couldn’t compare “\(font.displayName)” with your library")
                return
            }
            if similarFamilyID == nil, documentList == nil, externalSimilar == nil {
                listReturn = selectedItems
                listReturnPage = openFamilyID
            }
            clearSearch()
            selection = nil
            similarFamilyID = nil
            documentList = nil
            externalSimilar = DocumentList(name: font.displayName, families: nearest)
            openFamilyID = nil
            selectedIDs = []
        }
    }

    func libraryFamilies(of report: DocumentFontsReport) -> [String] {
        var seen = Set<String>()
        return documentMatches(report).compactMap(\.family).filter { seen.insert($0).inserted }
    }

    func showInLibrary(_ report: DocumentFontsReport) {
        if similarFamilyID == nil, documentList == nil, externalSimilar == nil {
            listReturn = selectedItems
            listReturnPage = openFamilyID
        }
        clearSearch()
        selection = nil
        similarFamilyID = nil
        externalSimilar = nil
        documentList = DocumentList(name: report.name, families: libraryFamilies(of: report))
        openFamilyID = nil
        selectedIDs = []
    }

    func endDocumentList() {
        guard documentList != nil else { return }
        returnFromList()
    }

    func showFonts(_ fonts: [DocumentFont], ofDocumentNamed name: String) {
        guard !fonts.isEmpty else { return showToast("“\(name)” doesn’t list any fonts") }
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
