import CiceroCore
import SwiftUI

struct RandomTextMenu: View {
    let place: SampleSources.Place
    let current: () -> String?
    let wholeParagraph: Bool
    let apply: (String) -> Void
    let showMessage: (String) -> Void

    private var sources: SampleSources { .shared }

    var body: some View {
        Button("Pangram", systemImage: "die.face.5") { apply(Pangrams.random(other: current() ?? "")) }
        let shortList = sources.shortList
        Menu {
            ForEach(shortList, id: \.self) { item($0) }
            Divider()
            Menu("Other Languages") {
                ForEach(SampleSources.byName.filter { !shortList.contains($0) }, id: \.self) { item($0) }
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
        let place = place, wholeParagraph = wholeParagraph, current = current, apply = apply, showMessage = showMessage
        guard let asked = current() else { return }
        let sources = SampleSources.shared
        sources.start(at: place) {
            do {
                let article = try await sources.article(in: language)
                guard !Task.isCancelled, current() == asked else { return }
                apply(wholeParagraph ? article.text : article.opening)
            } catch {
                guard !Task.isCancelled, current() == asked else { return }
                showMessage(Self.message(for: error))
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut:
            "Wikipedia took too long to answer. Try again."
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed:
            "Cicero couldn’t reach Wikipedia. Check your internet connection and try again."
        default:
            error is URLError ? "Cicero couldn’t reach Wikipedia. Try again."
                : "Wikipedia didn’t send a text. Try again later."
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

struct WikipediaCredit: View {
    let article: WikipediaArticle

    var body: some View {
        let language = Locale(identifier: "en").localizedString(forLanguageCode: article.language) ?? article.language
        // In an isolate, so the arrow stays after a title in Arabic or Hebrew.
        var title = AttributedString("\u{2068}\(article.title)\u{2069} ↗")
        title.link = article.url
        return Text(AttributedString("From Wikipedia in \(language): ") + title + AttributedString(" · CC BY-SA 4.0"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Open the article. Wikipedia’s texts are under the CC BY-SA 4.0 license.")
    }
}
