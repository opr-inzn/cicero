import AppKit
import CoreText
import SwiftUI

enum CompareLayout: String {
    case stacked, overlay
}

/// One family in the comparison, set in the face nearest the preview weight.
struct CompareEntry: Identifiable {
    var family: FontFamily
    var face: LibraryFace
    var font: CTFont
    var tint: Color

    var id: String { family.id }

    static let tints: [Color] = [.blue, .red, .green, .orange, .purple, .teal, .pink, .indigo, .brown, .cyan]
}

/// The Compare window: the same sample in every chosen family, stacked on a shared baseline or
/// drawn over each other. Families can be dragged in from the main window.
struct CompareView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PreviewSettings.self) private var preview
    @AppStorage("compare.layout") private var layout: CompareLayout = .stacked
    @State private var isTargeted = false

    var body: some View {
        let entries = library.presentation.compareIDs.compactMap(library.family(named:)).enumerated().map { index, family in
            let face = family.face(nearestWeight: Int(preview.weight))
            return CompareEntry(
                family: family, face: face,
                font: FontCache.shared.font(face.face, size: preview.size, weight: preview.weight),
                tint: CompareEntry.tints[index % CompareEntry.tints.count]
            )
        }
        // The comparison needs one text for every font, so an empty sample falls back to a classic test word.
        let sample = preview.sampleText.isEmpty ? "Hamburgefonstiv" : preview.sampleText
        let kerning = preview.kerning(atSize: preview.size)
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing to Compare", systemImage: "square.on.square",
                                       description: Text("Select two or more fonts and choose Compare, or drag fonts here from the main window."))
            } else {
                switch layout {
                case .stacked: StackedCompare(entries: entries, sample: sample, kerning: kerning)
                case .overlay: OverlayCompare(entries: entries, sample: sample, kerning: kerning)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .dropDestination(for: String.self) { names, _ in
            library.addToCompare(names)
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
            }
        }
        .navigationTitle("Compare")
        .navigationSubtitle(entries.count == 1 ? "1 family" : "\(entries.count) families")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layout", selection: $layout) {
                    Label("Stacked", systemImage: "rectangle.split.1x2").tag(CompareLayout.stacked)
                    Label("Overlay", systemImage: "square.on.square").tag(CompareLayout.overlay)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Stack the samples, or draw them over each other")
            }
            ToolbarItem { PreviewOptionsButton() }
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

/// A name chip with the entry's tint and a remove button.
private struct CompareLegendItem: View {
    @Environment(LibraryStore.self) private var library
    let entry: CompareEntry

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(entry.tint).frame(width: 8, height: 8)
            Text(entry.family.name).font(.callout)
            Text(entry.face.face.styleName).font(.callout).foregroundStyle(.secondary)
            Button {
                library.removeFromCompare(entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove from the comparison")
        }
        .lineLimit(1)
    }
}

// MARK: - Stacked

/// One row per font. Every row is the same height and puts its baseline at the same place, so
/// x-heights and cap heights line up down the page.
private struct StackedCompare: View {
    let entries: [CompareEntry]
    let sample: String
    let kerning: Double

    var body: some View {
        let ascent = entries.map { CTFontGetAscent($0.font) }.max() ?? 0
        let descent = entries.map { CTFontGetDescent($0.font) }.max() ?? 0
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .bottomLeading) {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(height: 1)
                                .padding(.bottom, descent)
                            Text(sample)
                                .font(Font(entry.font))
                                .kerning(kerning)
                                .lineLimit(1)
                                .fixedSize()
                                .alignmentGuide(.bottom) { $0[.lastTextBaseline] + descent }
                        }
                        .frame(height: ascent + descent, alignment: .bottomLeading)
                        CompareLegendItem(entry: entry)
                    }
                }
            }
            .padding(24)
        }
        .defaultScrollAnchor(.topLeading, for: .alignment)
    }
}

// MARK: - Overlay

/// Every sample drawn on one baseline in its own tint, to compare widths and proportions.
private struct OverlayCompare: View {
    let entries: [CompareEntry]
    let sample: String
    let kerning: Double
    @Environment(\.colorScheme) private var colorScheme

    private struct Line {
        var line: CTLine
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        var xHeight: CGFloat
        var capHeight: CGFloat
        var color: CGColor
    }

    var body: some View {
        let lines = entries.map(line(for:))
        let inset: CGFloat = 32
        let ascent = lines.map(\.ascent).max() ?? 0
        let descent = lines.map(\.descent).max() ?? 0
        let width = lines.map(\.width).max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 18, lineSpacing: 6) {
                ForEach(entries) { CompareLegendItem(entry: $0) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Canvas { context, size in
                    let baseline = inset + ascent
                    context.stroke(
                        Path { $0.move(to: CGPoint(x: 0, y: baseline)); $0.addLine(to: CGPoint(x: size.width, y: baseline)) },
                        with: .color(.secondary.opacity(0.35)), lineWidth: 1
                    )
                    // Short ticks at the left mark each font's x-height and cap height.
                    for line in lines {
                        for (height, length) in [(line.xHeight, 14.0), (line.capHeight, 8.0)] {
                            let y = baseline - height
                            context.stroke(
                                Path { $0.move(to: CGPoint(x: inset - 18, y: y)); $0.addLine(to: CGPoint(x: inset - 18 + length, y: y)) },
                                with: .color(Color(cgColor: line.color)), lineWidth: 1.5
                            )
                        }
                    }
                    context.withCGContext { cg in
                        // Multiplying inks on a light canvas (or screening them on a dark one) keeps overlaps readable.
                        cg.setBlendMode(colorScheme == .dark ? .screen : .multiply)
                        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                        for line in lines {
                            cg.textPosition = CGPoint(x: inset, y: baseline)
                            CTLineDraw(line.line, cg)
                        }
                    }
                }
                .frame(width: width + inset * 2, height: ascent + descent + inset * 2)
            }
        }
    }

    private func line(for entry: CompareEntry) -> Line {
        let color = NSColor(entry.tint).cgColor
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: entry.font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            kCTKernAttributeName as NSAttributedString.Key: kerning,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return Line(
            line: line, width: width, ascent: ascent, descent: descent,
            xHeight: CTFontGetXHeight(entry.font), capHeight: CTFontGetCapHeight(entry.font), color: color
        )
    }
}
