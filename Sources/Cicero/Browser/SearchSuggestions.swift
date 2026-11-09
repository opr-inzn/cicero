import AppKit
import CiceroCore
import SwiftUI

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
                SuggestionsHeader(title: "Filters")
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
                SuggestionsHeader(title: "Families")
            }
        }
    }
}

private struct SuggestionsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .padding(.top, 7)
            .padding(.bottom, -3)
    }
}

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
        case .variable: Image(systemName: "slider.horizontal.3").font(.system(size: 14))
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
