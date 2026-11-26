import CiceroCore
import SwiftUI

struct RandomTextMenu: View {
    let current: () -> String
    let wholeParagraph: Bool
    let apply: (String) -> Void
    let showMessage: (String) -> Void

    private var sources: SampleSources { .shared }

    var body: some View {
        Button("Pangram", systemImage: "dice") { apply(Pangrams.random(other: current())) }
        Menu {
            Section("Get a paragraph in") {
                ForEach(sources.shortList, id: \.self) { item($0) }
            }
            Divider()
            Menu("Other Languages") {
                ForEach(SampleSources.byName, id: \.self) { item($0) }
            }
        } label: {
            Label("Wikipedia", systemImage: "globe")
        }
    }

    private func item(_ language: String) -> some View {
        Toggle(SampleSources.name(of: language), isOn: Binding { sources.language == language } set: { _ in fetch(language) })
    }

    private func fetch(_ language: String) {
        let wholeParagraph = wholeParagraph, apply = apply, showMessage = showMessage
        Task {
            do {
                let article = try await SampleSources.shared.article(in: language)
                apply(wholeParagraph ? article.text : article.opening(length: SampleSources.previewLength))
            } catch {
                showMessage("Wikipedia didn’t answer. Check your internet connection and try again")
            }
        }
    }
}
