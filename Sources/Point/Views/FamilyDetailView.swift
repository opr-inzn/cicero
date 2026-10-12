import AppKit
import SwiftUI

struct FamilyDetailView: View {
    @Environment(LibraryStore.self) private var library
    let family: FontFamily

    @AppStorage(Prefs.detailPointSize) private var pointSize = 64.0
    @AppStorage(Prefs.detailWeight) private var weight = 400.0
    @AppStorage(Prefs.detailTracking) private var tracking = 0.0
    @AppStorage(Prefs.detailText) private var previewText = "The quick brown fox jumps over the lazy dog."
    @AppStorage(Prefs.colorMode) private var colorMode: PreviewColorMode = .light
    @AppStorage(Prefs.customForeground) private var customForeground = "#FFFFFF"
    @AppStorage(Prefs.customBackground) private var customBackground = "#F04000"

    @State private var sections: [CharacterSection] = []
    @State private var selectedCharacter: UInt32?

    private static let pangrams = [
        "Sphinx of black quartz, judge my vow.",
        "The five boxing wizards jump quickly.",
        "Pack my box with five dozen liquor jugs.",
        "Trains leave at 06:40, 13:15 & 21:50, platform 9.",
        "How vexingly quick daft zebras jump.",
        "Jackdaws love my big sphinx of quartz.",
        "SMALL TYPE, BIG IDEAS (EST. 2026).",
        "Waltz, bad nymph, for quick jigs vex.",
    ]

    var body: some View {
        let colors = PreviewColors(mode: colorMode, foregroundHex: customForeground, backgroundHex: customBackground)
        let face = family.face(nearestWeight: Int(weight))
        let features = library.detailFeatures
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Type something", text: $previewText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Font(FontCache.shared.font(face.face, size: pointSize, weight: weight, features: features)))
                    .tracking(pointSize * tracking / 100)
                    .foregroundStyle(colors.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity, minHeight: 340)

                VStack(spacing: 0) {
                    ForEach(Array(family.faces.enumerated()), id: \.element.id) { index, style in
                        styleRow(style, index: index, colors: colors)
                    }
                }
                .padding(.horizontal, 24)

                ForEach(sections) { section in
                    characterSection(section, face: face.face, colors: colors)
                }
            }
            .padding(.bottom, 40)
        }
        .background(colors.background)
        .navigationTitle(family.name)
        .toolbar { toolbar }
        .onExitCommand { library.detailFamilyID = nil }
        .task(id: face.id) {
            let target = face.face
            sections = await Task.detached(priority: .userInitiated) { CharacterSections.compute(for: target) }.value
        }
    }

    // MARK: Styles

    private func styleRow(_ style: LibraryFace, index: Int, colors: PreviewColors) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(style.face.styleName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if style.status != .active(.user) && style.status != .active(.registered) {
                    Text(style.status.label)
                        .font(.system(size: 9))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(colors.foreground.opacity(0.55))
            .frame(width: 120, alignment: .leading)
            FontPreviewText(
                text: Self.pangrams[index % Self.pangrams.count],
                face: style.face, size: 28, weight: Double(style.face.weightClass), features: library.detailFeatures, color: colors.foreground
            )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(colors.foreground.opacity(0.08)).frame(height: 1) }
        .contentShape(.rect)
        .contextMenu { FaceActionsMenu(family: family, face: style) }
    }

    // MARK: Characters

    private func characterSection(_ section: CharacterSection, face: FontFace, colors: PreviewColors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.foreground.opacity(0.5))
                .padding(.horizontal, 24)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 0)], spacing: 0) {
                ForEach(section.scalars, id: \.self) { value in
                    characterCell(value, face: face, colors: colors)
                }
            }
        }
        .padding(.top, 36)
    }

    private func characterCell(_ value: UInt32, face: FontFace, colors: PreviewColors) -> some View {
        let character = String(Unicode.Scalar(value).map(Character.init) ?? " ")
        return Text(character)
            .font(Font(FontCache.shared.font(face, size: 30, weight: weight, features: library.detailFeatures)))
            .foregroundStyle(colors.foreground)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selectedCharacter == value ? Color.accentColor.opacity(0.18) : .clear)
            .overlay { Rectangle().strokeBorder(colors.foreground.opacity(0.07), lineWidth: 0.5) }
            .contentShape(.rect)
            .onTapGesture { selectedCharacter = value }
            .popover(isPresented: Binding(
                get: { selectedCharacter == value },
                set: { if !$0 { selectedCharacter = nil } }
            )) {
                CharacterPopover(value: value, face: face, weight: weight)
            }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                library.detailFamilyID = nil
            } label: {
                Image(systemName: "chevron.backward")
            }
            .help("Back to all fonts")
        }

        ToolbarItem {
            SliderMenuControl(value: $pointSize, range: 8...300, presets: [24, 36, 48, 64, 96, 144, 200], unit: " pt")
                .help("Preview size")
        }
        ToolbarItem {
            SliderMenuControl(value: $weight, range: 100...900, presets: [100, 200, 300, 400, 500, 600, 700, 800, 900], unit: "")
                .help("Weight")
        }
        ToolbarItem {
            HStack(spacing: 6) {
                Slider(value: $tracking, in: -10...50)
                    .controlSize(.mini)
                    .frame(width: 84)
                Menu(String(format: "%.1f%%", tracking)) {
                    ForEach([-5.0, -2.5, 0, 2.5, 5, 10, 20], id: \.self) { value in
                        Button(String(format: "%.1f%%", value)) { tracking = value }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .help("Letter spacing")
        }
        ToolbarItem {
            ColorChips(mode: $colorMode, foregroundHex: $customForeground, backgroundHex: $customBackground)
        }
        ToolbarItem { InfoToolbarButton() }
            .sharedBackgroundVisibility(.hidden)
    }
}

struct CharacterPopover: View {
    let value: UInt32
    let face: FontFace
    let weight: Double

    var body: some View {
        let scalar = Unicode.Scalar(value)
        let character = scalar.map { String(Character($0)) } ?? ""
        VStack(spacing: 10) {
            Text(character)
                .font(Font(FontCache.shared.font(face, size: 120, weight: weight)))
                .frame(minWidth: 180, minHeight: 160)
            Text(scalar?.properties.name?.capitalized ?? scalar?.properties.nameAlias?.capitalized ?? "Unnamed")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
            Text(String(format: "U+%04X", value))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Copy Character") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(character, forType: .string)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 240)
    }
}
