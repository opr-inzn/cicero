import CiceroCore
import SwiftUI

struct RandomTextMenu: View {
    let current: () -> String?
    let wholeParagraph: Bool
    var started: () -> Void = {}
    let apply: (String) -> Void
    let showMessage: (String) -> Void

    private var sources: SampleSources { .shared }

    var body: some View {
        Button("Pangram", systemImage: "die.face.5") { apply(Pangrams.random(other: current() ?? "")) }
        Menu {
            ForEach(sources.shortList, id: \.self) { item($0) }
            Divider()
            Menu("Other Languages") {
                ForEach(SampleSources.byName, id: \.self) { item($0) }
            }
        } label: {
            Label { Text("Wikipedia") } icon: { Image(nsImage: .wikipedia) }
                .labelStyle(.titleAndIcon)
        }
    }

    private func item(_ language: String) -> some View {
        Button(SampleSources.name(of: language)) { fetch(language) }
    }

    private func fetch(_ language: String) {
        let wholeParagraph = wholeParagraph, current = current, apply = apply, showMessage = showMessage
        guard let asked = current() else { return }
        started()
        SampleSources.shared.start {
            do {
                let article = try await SampleSources.shared.article(in: language)
                guard !Task.isCancelled, current() == asked else { return }
                apply(wholeParagraph ? article.text : article.opening)
            } catch {
                guard !Task.isCancelled, current() == asked else { return }
                showMessage("Cicero couldn’t get a text from Wikipedia. Check your internet connection and try again.")
            }
        }
    }
}

private extension NSImage {
    static let wikipedia: NSImage = {
        func line(size: CGFloat) -> CTLine {
            let font = NSFont(name: "Hoefler Text", size: size) ?? NSFont.systemFont(ofSize: size)
            return CTLineCreateWithAttributedString(NSAttributedString(string: "W", attributes: [.font: font]))
        }
        let height = NSFont.menuFont(ofSize: 0).capHeight
        let line = line(size: 100 * height / CTLineGetBoundsWithOptions(line(size: 100), .useGlyphPathBounds).height)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let image = NSImage(size: NSSize(width: ink.width.rounded(.up), height: 16), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.textPosition = CGPoint(x: (rect.width - ink.width) / 2 - ink.minX, y: (rect.height - ink.height) / 2 - ink.minY)
            CTLineDraw(line, context)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
