import CiceroCore
import SwiftUI

/// The families the search field suggests as something is typed, each with "Aa" in its regular style. Choosing one
/// puts its whole name in the field, which selects it among the matches and brings it into view.
struct SearchSuggestions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let families = model.searchSuggestions(for: model.searchText)
        if !families.isEmpty {
            Section("Families") {
                ForEach(families) { family in
                    Label {
                        Text(family.name)
                    } icon: {
                        // A fixed width keeps the names lined up however wide each family's letters are.
                        FontText(text: "Aa", face: family.regular.face, size: 14, weight: family.regular.face.styleWeight)
                            .frame(width: 28)
                    }
                    .searchCompletion(family.name)
                }
            }
        }
    }
}
