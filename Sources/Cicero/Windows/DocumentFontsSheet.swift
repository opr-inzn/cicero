import CiceroCore
import SwiftUI

/// The fonts a document uses, each against the library: active, active in the apps that load them from their own
/// folder only, in the library but inactive (both with Activate), or missing. Below, everything available turned on at
/// once.
struct DocumentFontsSheet: View {
    let report: DocumentFontsReport
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var model = model
        let matches = sorted(model.documentMatches(report))
        let off = matches.filter { $0.face?.canActivate == true && !isOn($0) }
        let inApps = off.compactMap(appOnly)
        let missing = matches.filter { $0.face == nil && !$0.isInstalled }
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fonts in “\(report.name)”").font(.title2.bold()).lineLimit(1).truncationMode(.middle)
                Text(summary(matches.count, active: matches.count - off.count - missing.count, inApps: inApps,
                             inactive: off.count - inApps.count, missing: missing.count))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { match in
                        row(match)
                        if match.id != matches.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                // Only when the library has some of them.
                if !model.libraryFamilies(of: report).isEmpty {
                    Button("Show in Library") {
                        model.showInLibrary(report)
                        dismiss()
                    }
                    .help("Shows the document’s fonts from your library in the main window")
                }
                Button("Activate All") { model.activateAll(in: report) }
                    .disabled(off.isEmpty)
                    .help("Turns on every font of the document that’s in your library")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 540)
        // The main window can't show a sheet over this one, so adding a font file asks how from here.
        .sheet(item: $model.installPrompt) { InstallSheet(prompt: $0) }
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
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).accessibilityLabel("Active")
        } else if let app = appOnly(match) {
            // In the red of the Proofing tag (see `StatusTag`).
            Image(systemName: "checkmark.seal").foregroundStyle(.red).accessibilityLabel("Active in \(app)")
        } else if match.face != nil {
            Image(systemName: "xmark.seal").foregroundStyle(.secondary).accessibilityLabel("Inactive")
        } else {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Missing")
        }
    }

    private func statusText(_ match: DocumentFontMatch) -> String {
        if let face = match.face { return face.state.label }
        return match.isInstalled ? "Installed with macOS" : "Not in your library"
    }

    @ViewBuilder
    private func action(_ match: DocumentFontMatch) -> some View {
        if let face = match.face {
            if face.canActivate && !isOn(match) {
                // As the family's menu says it (see `ActivationTitles`).
                Button(face.app != nil ? "Activate in All Apps" : "Activate") {
                    model.activate([face], title: match.font.displayName)
                }
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

    /// "Adobe apps" or "InDesign" for a face on only in the apps that load it from their own folder, else nil.
    private func appOnly(_ match: DocumentFontMatch) -> String? {
        guard case .appOnly(let app) = match.face?.state else { return nil }
        return FaceState.appDescription(app)
    }

    /// Missing first, then off, then on in some apps only, then on; each by name.
    private func sorted(_ matches: [DocumentFontMatch]) -> [DocumentFontMatch] {
        func rank(_ match: DocumentFontMatch) -> Int {
            match.face == nil && !match.isInstalled ? 0 : isOn(match) ? 3 : appOnly(match) != nil ? 2 : 1
        }
        return matches.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : title(a).localizedStandardCompare(title(b)) == .orderedAscending
        }
    }

    /// "12 fonts · 8 active · 2 in Adobe apps · 1 inactive · 1 missing", as the rest of the app says it: one count for
    /// each app the fonts are on in only, in the order the rows have them.
    private func summary(_ total: Int, active: Int, inApps: [String], inactive: Int, missing: Int) -> String {
        var parts = [total == 1 ? "1 font" : "\(total) fonts", "\(active) active"]
        var apps: [String] = []
        for app in inApps where !apps.contains(app) { apps.append(app) }
        parts += apps.map { app in "\(inApps.count { $0 == app }) in \(app)" }
        if inactive > 0 { parts.append("\(inactive) inactive") }
        if missing > 0 { parts.append("\(missing) missing") }
        return parts.joined(separator: " · ")
    }
}
