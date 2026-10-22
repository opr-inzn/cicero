import AppKit
import CiceroCore
import SwiftUI

/// What the search field suggests as something is typed: the filters whose names the last words begin (see
/// `SearchToken`), each with a sample of what it asks for, which choosing makes a token in the field; then the families,
/// each with "Aa" in its regular style, of which choosing one puts its whole name in the field, which selects it among
/// the matches and brings it into view.
struct SearchSuggestions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tokens = model.tokenSuggestions(for: model.searchText)
        if !tokens.isEmpty {
            Section {
                ForEach(tokens) { token in
                    Label {
                        Text(token.title)
                    } icon: {
                        TokenSample(token: token)
                            .frame(width: 28)
                            .padding(.trailing, 2)
                    }
                    .searchCompletion(token)
                }
            } header: {
                SuggestionsHeader(title: "Filters", isFirst: true)
            }
        }
        let families = model.searchSuggestions(for: model.searchText)
        if !families.isEmpty {
            Section {
                ForEach(families) { family in
                    Label {
                        Text(family.name)
                    } icon: {
                        // A fixed width keeps the names lined up however wide each family's letters are, and a little
                        // room after it keeps a wide Aa from running into its name.
                        FontText(text: "Aa", face: family.regular.face, size: 14, weight: family.regular.face.styleWeight)
                            .frame(width: 28)
                            .padding(.trailing, 2)
                    }
                    .searchCompletion(family.name)
                }
            } header: {
                SuggestionsHeader(title: "Families", isFirst: tokens.isEmpty)
            }
        }
    }
}

/// A section's title, nearer its own rows than the ones before it: the list puts it midway between them.
private struct SuggestionsHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        Text(title)
            .padding(.top, isFirst ? 0 : 6)
            .padding(.bottom, -4)
    }
}

/// What a filter asks for, in the system's fonts: "Aa" in italic, of a weight or of a width, "123" in tabular or
/// old-style figures (in New York, as the system's sans serif has none of those).
private struct TokenSample: View {
    let token: SearchToken

    var body: some View {
        switch token {
        case .italic: Text("Aa").font(.system(size: 14)).italic()
        case .weight(let weight): Text("Aa").font(.system(size: 14, weight: Self.weight(weight)))
        case .condensed: Text("Aa").font(.system(size: 14)).fontWidth(.condensed)
        case .extended: Text("Aa").font(.system(size: 14)).fontWidth(.expanded)
        case .tabularFigures: Text("123").font(.system(size: 14)).monospacedDigit()
        case .oldStyleFigures: Text("123").font(Self.oldStyle)
        }
    }

    private static func weight(_ weight: Int) -> Font.Weight {
        [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black][min(max(weight / 100, 1), 9) - 1]
    }

    private static let oldStyle: Font = {
        let system = NSFont.systemFont(ofSize: 14)
        let serif = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        let descriptor = serif.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberCaseType, .selectorIdentifier: kLowerCaseNumbersSelector,
        ]]])
        return Font(NSFont(descriptor: descriptor, size: 14) ?? system)
    }()
}
