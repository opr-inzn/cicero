import PointCore
import SwiftUI

/// Every character a style has, grouped, with a filter by character, Unicode name or U+ code.
struct GlyphsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(PreviewSettings.self) private var preview
    let family: Family
    @State private var sections: [GlyphSection]?
    @State private var query = ""
    @State private var popover: UInt32?

    private let cell: CGFloat = 52

    var body: some View {
        let face = family.face(nearestWeight: preview.weight).face
        let shown = filtered(sections ?? [])
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $query, prompt: Text("Character, name or U+ code"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                if let sections {
                    let total = sections.reduce(0) { $0 + $1.scalars.count }
                    Text(total == 1 ? "1 character" : "\(total.formatted()) characters")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            if sections == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No Characters" : "No Matching Characters", systemImage: "character",
                                       description: Text(query.isEmpty ? "Point couldn’t read the characters in this font." : "Try a character, part of its name, or a code like U+00E9."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                        ForEach(shown) { section in
                            Section {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 4)], alignment: .leading, spacing: 4) {
                                    ForEach(section.scalars, id: \.self) { scalar in
                                        glyph(scalar, face: face)
                                    }
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(section.title).font(.headline)
                                    Text("— \(section.scalars.count.formatted())").font(.callout).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .background(Color.canvas)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .task(id: face.id) {
            sections = nil
            let ranges = await model.coverage.coverage(computing: face).scalars
            sections = await Task.detached(priority: .userInitiated) { GlyphSection.sections(for: ranges) }.value
        }
    }

    private func glyph(_ scalar: UInt32, face: FontFace) -> some View {
        FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: face, size: 26, weight: preview.weight, features: model.features(for: family))
            .frame(width: cell, height: cell)
            .background(.quaternary.opacity(popover == scalar ? 0.9 : 0.35), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture { popover = scalar }
            .popover(isPresented: Binding(get: { popover == scalar }, set: { if !$0 { popover = nil } })) {
                VStack(spacing: 10) {
                    FontText(text: String(Character(Unicode.Scalar(scalar)!)), face: face, size: 96, weight: preview.weight)
                        .frame(minWidth: 160, minHeight: 130)
                    Text(GlyphSection.name(of: scalar)?.capitalized ?? "Unnamed").font(.callout).multilineTextAlignment(.center)
                    Text(String(format: "U+%04X", scalar)).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: 260)
            }
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
