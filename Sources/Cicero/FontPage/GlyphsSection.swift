import CiceroCore
import SwiftUI

/// Every character a style has, grouped, with a filter by character, Unicode name or U+ code. Several
/// views in a row, so each block's header pins in the page's lazy stack and its cells are rows of it.
struct GlyphsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    /// Cells per row, from the page's width; nil until it's known.
    let columns: Int?
    /// The style's characters, loaded by the page; nil while loading.
    let sections: [GlyphSection]?
    @State private var query = ""
    @State private var popover: UInt32?

    private nonisolated static let cell: CGFloat = 52
    private nonisolated static let spacing: CGFloat = 4
    private nonisolated static let inset: CGFloat = 24

    /// How many cells fit across a page this wide.
    nonisolated static func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + spacing) / (cell + spacing)))
    }

    var body: some View {
        let face = family.face(nearestWeight: preview.weight).face
        let shown = filtered(sections ?? [])
        HStack(spacing: 12) {
            Text("Glyphs").font(.title2.weight(.semibold))
            if let sections {
                let total = sections.reduce(0) { $0 + $1.scalars.count }
                Text(total == 1 ? "1 character" : "\(total.formatted()) characters")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            TextField("Filter", text: $query, prompt: Text("Character, name or U+ code"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
        }
        .padding(.horizontal, Self.inset)
        // Well clear of the styles above, and close to the blocks it heads.
        .padding(.top, 56)
        .padding(.bottom, 4)
        if sections == nil {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        } else if shown.isEmpty {
            ContentUnavailableView(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                                   description: Text(query.isEmpty ? "Cicero couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
                .padding(.vertical, 40)
        } else if let columns {
            ForEach(shown) { section in
                Section {
                    // Rows of the page's stack, not a LazyVGrid per block in it. The stack guesses the height of blocks
                    // it hasn't placed from those it has, and blocks run from one row to hundreds, so every correction
                    // shifted the page and changed which blocks were placed: it re-laid itself out at full CPU. Rows
                    // of fixed cells are all one height, so the guesses are right.
                    let rows = (section.scalars.count + columns - 1) / columns
                    ForEach(0..<rows, id: \.self) { row in
                        glyphRow(section.scalars[row * columns ..< min((row + 1) * columns, section.scalars.count)], face: face)
                            .padding(.horizontal, Self.inset)
                            .padding(.bottom, row == rows - 1 ? 18 : Self.spacing)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(section.title).font(.headline)
                        Text("— \(section.scalars.count.formatted())").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 4)
                    .background(Color.canvas)
                }
            }
            Color.clear.frame(height: 6)
        }
    }

    /// One popover per row, pointing at the clicked cell, rather than one per cell: each is worked out
    /// again whenever the page updates.
    private func glyphRow(_ scalars: ArraySlice<UInt32>, face: FontFace) -> some View {
        let column = popover.flatMap { scalars.firstIndex(of: $0) }.map { $0 - scalars.startIndex }
        let anchor = CGRect(x: CGFloat(column ?? 0) * (Self.cell + Self.spacing), y: 0, width: Self.cell, height: Self.cell)
        return HStack(spacing: Self.spacing) {
            ForEach(scalars, id: \.self) { scalar in
                glyph(scalar, face: face)
            }
        }
        .popover(isPresented: Binding(get: { column != nil }, set: { if !$0 { popover = nil } }), attachmentAnchor: .rect(.rect(anchor))) {
            if let popover {
                VStack(spacing: 10) {
                    FontText(text: String(Character(Unicode.Scalar(popover)!)), face: face, size: 96, weight: preview.weight)
                        .frame(minWidth: 160, minHeight: 130)
                    Text(GlyphSection.name(of: popover)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                    Text(String(format: "U+%04X", popover)).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: 260)
            }
        }
    }

    private func glyph(_ scalar: UInt32, face: FontFace) -> some View {
        FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: face, size: 26, weight: preview.weight, features: model.features(for: family))
            .frame(width: Self.cell, height: Self.cell)
            .background(.quaternary.opacity(popover == scalar ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture { popover = scalar }
    }

    private func filtered(_ sections: [GlyphSection]) -> [GlyphSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sections }
        let code = trimmed.uppercased().replacingOccurrences(of: "U+", with: "").replacingOccurrences(of: "0X", with: "")
        let codeValue = UInt32(code, radix: 16)
        let scalars = Set(trimmed.unicodeScalars.map(\.value))
        let lower = trimmed.lowercased()
        return sections.compactMap { section in
            let matches = section.scalars.filter { scalar in
                scalars.contains(scalar) || scalar == codeValue
                    || (trimmed.count > 1 && (GlyphSection.name(of: scalar)?.lowercased().contains(lower) ?? false))
            }
            return matches.isEmpty ? nil : GlyphSection(title: section.title, scalars: matches)
        }
    }
}
