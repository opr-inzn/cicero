import SwiftUI

enum FontPageTab: String, CaseIterable {
    case text, waterfall, styles, glyphs

    var title: String {
        switch self {
        case .text: "Text"
        case .waterfall: "Waterfall"
        case .styles: "Styles"
        case .glyphs: "Glyphs"
        }
    }
}

/// One family's page, pushed over the browser: a header band, then whichever tab was last used.
struct FontPage: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("fontPage.view") private var tab: FontPageTab = .text
    let familyID: String

    var body: some View {
        if let family = library.family(named: familyID) {
            page(family)
        } else {
            // The store clears `detailFamilyID` when a family disappears, which pops this page.
            ContentUnavailableView("Font Not Available", systemImage: "textformat",
                                   description: Text("This font is no longer in your library."))
                .background(Color.canvas)
                .onExitCommand { library.detailFamilyID = nil }
        }
    }

    private func page(_ family: FontFamily) -> some View {
        VStack(spacing: 0) {
            FontPageHeader(family: family)
            Divider()
            switch tab {
            case .text: TypeTester(family: family)
            case .waterfall: WaterfallView(family: family)
            case .styles: StylesTable(family: family)
            case .glyphs: GlyphGrid(family: family)
            }
        }
        .background(Color.canvas)
        .navigationTitle(family.name)
        .toolbar { toolbar }
        .modifier(LibraryInspector())
        .onExitCommand { library.detailFamilyID = nil }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $tab) {
                ForEach(FontPageTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        ToolbarSpacer(.fixed)
        ToolbarItem { PreviewOptionsButton() }
        ToolbarSpacer(.fixed)
        ToolbarItem { InfoToolbarButton() }
    }
}

// MARK: - Header

/// The family name in its own typeface, a line of facts about it, and the whole-family switch.
private struct FontPageHeader: View {
    @Environment(LibraryStore.self) private var library
    let family: FontFamily

    var body: some View {
        let face = family.face(nearestWeight: 400).face
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(family.name)
                    .font(Font(FontCache.shared.font(face, size: 34, weight: 400)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            FamilyActivationButtons(family: family)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var summary: String {
        var parts: [String] = []
        if let foundry = library.foundryName(of: family) { parts.append(foundry) }
        parts.append(family.classification.rawValue)
        parts.append(family.format)
        if family.isVariable { parts.append("Variable") }
        parts.append("\(family.stylesLabel) · \(family.activeFaceCount) activated")
        return parts.joined(separator: " · ")
    }
}

/// Activate is the prominent action whenever any style is off; Deactivate sits beside it for
/// partly active families. Families Point can't change (system, app and Adobe fonts) get a disabled
/// button whose tooltip says why.
private struct FamilyActivationButtons: View {
    @Environment(LibraryStore.self) private var library
    let family: FontFamily

    var body: some View {
        HStack(spacing: 8) {
            if family.hasActivatableFaces {
                Button("Activate" + (library.data.installMethod == .ask ? "…" : "")) { library.requestActivate([family]) }
                    .buttonStyle(.borderedProminent)
                    .help(family.hasActiveFaces ? "Turn on the styles that are still off" : "Turn on every style, for all apps")
            } else if family.hasTemporaryFaces {
                Button("Activate Permanently" + (library.data.installMethod == .ask ? "…" : "")) { library.requestActivate([family]) }
                    .help("Keep these styles on after Point quits or you log out")
            }
            if family.hasDeactivatableFaces {
                Button("Deactivate") { library.requestDeactivate([family]) }
                    .help("Turn off every style Point manages")
            } else if !family.hasActivatableFaces {
                Button("Deactivate") {}
                    .disabled(true)
                    .help(lockedReason)
            }
        }
    }

    private var lockedReason: String {
        switch family.faces.first?.status {
        case .active(.system): "Installed with macOS, so it can’t be turned off"
        case .active(.allUsers): "Installed for all users; an administrator has to remove it"
        case .active(.application): "Belongs to an app, which manages it itself"
        case .active(.adobeCloud): "Managed by Adobe Creative Cloud"
        default: "Managed outside Point"
        }
    }
}
