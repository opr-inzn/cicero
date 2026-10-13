import AppKit
import CiceroCore
import UniformTypeIdentifiers

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
        panel.message = "Choose a PDF, IDML, InDesign or Illustrator file to see which fonts it uses."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        findFonts(in: url)
    }

    /// Reads which fonts the document uses, off the main thread, and shows them.
    func findFonts(in url: URL) {
        Task {
            let read = await Task.detached(priority: .userInitiated) { Result { try DocumentFonts.read(url) } }.value
            switch read {
            case .success(let fonts) where fonts.isEmpty:
                showToast("“\(url.lastPathComponent)” doesn’t name any fonts.")
            case .success(let fonts):
                documentFonts = DocumentFontsReport(url: url, fonts: fonts)
            case .failure:
                showToast("Couldn’t read the fonts in “\(url.lastPathComponent)”.")
            }
        }
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
            return "Added \(count) to the set “\(report.setName)”."
        }
        addSet(named: report.setName, with: families)
        return "Made the set “\(report.setName)” with \(count)."
    }

    /// Turns on every font of the document that's in the library and off.
    func activateAll(in report: DocumentFontsReport) {
        let faces = documentMatches(report).compactMap(\.face).filter(\.canActivate)
        guard !faces.isEmpty else { return }
        activate(faces, title: "the Fonts in “\(report.name)”")
    }
}
