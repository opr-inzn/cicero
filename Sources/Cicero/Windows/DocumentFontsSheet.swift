import CiceroCore
import SwiftUI

/// The fonts a document uses, each against the library: active, in the library but inactive (with Activate), or missing
/// (with Find on This Mac, which asks Spotlight for the file). Below, a set named after the document and
/// everything available turned on at once.
struct DocumentFontsSheet: View {
    let report: DocumentFontsReport
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// What Find on This Mac turned up for each missing font, by match.
    @State private var searches: [String: Search] = [:]
    /// What Make Set did.
    @State private var message: String?

    enum Search {
        case searching
        case found(String)
        case notFound
    }

    var body: some View {
        @Bindable var model = model
        let matches = sorted(model.documentMatches(report))
        let off = matches.filter { $0.face?.canActivate == true && !isOn($0) }
        let missing = matches.filter { $0.face == nil && !$0.isInstalled }
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fonts in “\(report.name)”").font(.title2.bold()).lineLimit(1).truncationMode(.middle)
                Text(summary(matches.count, active: matches.count - off.count - missing.count, inactive: off.count, missing: missing.count))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { match in
                        row(match)
                        Divider().padding(.leading, 48)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                if let message {
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Show in Library") {
                    model.showInLibrary(report)
                    dismiss()
                }
                .disabled(model.libraryFamilies(of: report).isEmpty)
                .help("Shows the document’s fonts that are in your library in the main window, each set in itself")
                Button("Make Set") { message = model.makeSet(for: report) }
                    .help("A set named “\(report.setName)” with the document’s fonts that are in your library")
                Button("Activate All") { model.activateAll(in: report) }
                    .disabled(off.isEmpty)
                    .help("Turns on every font of the document that’s in your library")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 540)
        // The main window can't show a sheet over this one, so activating asks how from here.
        .sheet(item: $model.activationPrompt) { ActivationSheet(prompt: $0) }
        .confirmsManyActivations()
    }

    // MARK: Rows

    private func row(_ match: DocumentFontMatch) -> some View {
        HStack(spacing: 12) {
            statusIcon(match)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title(match)).lineLimit(1)
                    if match.font.isEmbedded == true {
                        Tag(text: "Embedded", tint: .secondary)
                            .help("The PDF carries the font, so it shows as it should even where the font is missing.")
                    }
                }
                if let postScriptName = match.font.postScriptName, postScriptName != title(match) {
                    Text(postScriptName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(statusText(match))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            action(match)
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func statusIcon(_ match: DocumentFontMatch) -> some View {
        if isOn(match) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Active")
        } else if match.face != nil {
            Image(systemName: "circle.dashed").foregroundStyle(.secondary).accessibilityLabel("Inactive")
        } else {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Missing")
        }
    }

    private func statusText(_ match: DocumentFontMatch) -> String {
        if let face = match.face { return face.state.label }
        if match.isInstalled { return "Installed with macOS" }
        switch searches[match.id] {
        case .searching: return "Searching"
        case .found(let path): return "Found “\(URL(fileURLWithPath: path).lastPathComponent)”"
        case .notFound: return "Not found on this Mac"
        case nil: return "Not in your library"
        }
    }

    @ViewBuilder
    private func action(_ match: DocumentFontMatch) -> some View {
        if let face = match.face {
            if face.canActivate && !isOn(match) {
                Button("Activate") {
                    model.activate([face], title: match.font.displayName)
                }
            }
        } else if !match.isInstalled, let postScriptName = match.font.postScriptName {
            switch searches[match.id] {
            case .found(let path):
                // Copied even when fonts are activated by moving: Spotlight may have found it in another document's folder.
                if model.installsAddedFiles {
                    Button("Install") { model.addFontFiles([path], mayMove: false) }
                        .help("Copies the file into \(model.installPlace) and turns it on")
                } else {
                    Button("Add") { model.addFontFiles([path]) }
                        .help("Lists the file in your library where it is, under Added Fonts")
                }
            case .searching:
                ProgressView().controlSize(.small)
            case nil, .notFound:
                Button("Find on This Mac") { find(postScriptName, for: match.id) }
                    .help("Looks for the font file with Spotlight, on this Mac")
            }
        }
    }

    // MARK: Helpers

    /// The family and style as the library names them, else as the document does: a PDF gives only PostScript names.
    private func title(_ match: DocumentFontMatch) -> String {
        guard let face = match.face else { return match.font.displayName }
        return "\(match.family ?? face.face.familyName) \(face.face.styleName)"
    }

    /// On for apps: the library's face is on (in an app's own folder counts, for that app), or macOS has it.
    private func isOn(_ match: DocumentFontMatch) -> Bool {
        guard let face = match.face else { return match.isInstalled }
        return face.state.isActive
    }

    /// Missing first, then off, then on; each by name.
    private func sorted(_ matches: [DocumentFontMatch]) -> [DocumentFontMatch] {
        func rank(_ match: DocumentFontMatch) -> Int { match.face == nil && !match.isInstalled ? 0 : isOn(match) ? 2 : 1 }
        return matches.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : title(a).localizedStandardCompare(title(b)) == .orderedAscending
        }
    }

    /// Spotlight leaves out what's in folders macOS keeps private until the user lets an app in (Documents,
    /// Desktop, Downloads), without asking. Looking into them asks, once, so a font there can be found.
    @concurrent
    private static func askForFolders() async {
        let fm = FileManager.default
        for directory in [FileManager.SearchPathDirectory.documentDirectory, .desktopDirectory, .downloadsDirectory] {
            guard let url = fm.urls(for: directory, in: .userDomainMask).first else { continue }
            _ = try? fm.contentsOfDirectory(atPath: url.path)
        }
    }

    /// "12 fonts · 8 active · 2 inactive · 2 missing", as the rest of the app says it.
    private func summary(_ total: Int, active: Int, inactive: Int, missing: Int) -> String {
        var parts = [total == 1 ? "1 font" : "\(total) fonts", "\(active) active"]
        if inactive > 0 { parts.append("\(inactive) inactive") }
        if missing > 0 { parts.append("\(missing) missing") }
        return parts.joined(separator: " · ")
    }

    private func find(_ postScriptName: String, for id: String) {
        searches[id] = .searching
        Task {
            await Self.askForFolders()
            let paths = await FontFileSearch.files(withPostScriptName: postScriptName)
            searches[id] = paths.first.map(Search.found) ?? .notFound
        }
    }
}
