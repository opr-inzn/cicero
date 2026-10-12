import CiceroCore
import SwiftUI
import AppKit

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system
    @State private var isClearingCaches = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Activate fonts by", selection: $model.data.installMethod) {
                    ForEach(InstallMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("E labeled") {
                    Picker("E", selection: $model.data.installMethod) {
                        ForEach(InstallMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HStack {
                    Text("F hstack")
                    Spacer()
                    Picker("F", selection: $model.data.installMethod) {
                        ForEach(InstallMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                LabeledContent("G appkit") {
                    TestPopUp(titles: InstallMethod.allCases.map(\.title), index: Binding(
                        get: { InstallMethod.allCases.firstIndex(of: model.data.installMethod) ?? 0 },
                        set: { model.data.installMethod = InstallMethod.allCases[$0] }))
                    .fixedSize()
                }
            } header: {
                Text("Activation")
            } footer: {
                Text(activationExplanation)
            }
            Section {
                Toggle("Show system fonts in other lists", isOn: $model.data.showSystemFonts)
            } footer: {
                Text("Fonts that come with macOS are always in System Fonts. With this on, they’re in All Fonts, foundries, classifications and every other list too.")
            }
            Section {
                LabeledContent("Cicero’s font list") {
                    Button("Rebuild") { model.rebuildFontList() }
                }
                LabeledContent("macOS, Adobe and Office caches") {
                    Button("Clear…") { isClearingCaches = true }
                }
            } header: {
                Text("Font Caches")
            } footer: {
                Text("Rebuild reads every font file again. Clearing the caches helps when fonts don’t show up in apps or look wrong.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .fontCacheSheet(isPresented: $isClearingCaches)
    }

    private var activationExplanation: String {
        let method = switch model.data.installMethod {
        case .ask: "Cicero asks each time whether to copy the fonts into your Fonts folder or use them where they are."
        case .copy: "Cicero copies the font files into your Fonts folder. The originals stay where they are, and the fonts keep working if you move them."
        case .inPlace: "Cicero tells macOS to use the font files from where they are. Nothing is copied, but the fonts stop working if the files move or their disk is unplugged."
        }
        return method + " Fonts from a folder an app loads itself, like Adobe’s, are always used where they are."
    }
}

private extension InstallMethod {
    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .copy: "Copy into ~/Library/Fonts"
        case .inPlace: "Use the files where they are"
        }
    }
}

private struct TestPopUp: NSViewRepresentable {
    let titles: [String]
    @Binding var index: Int
    func makeNSView(context: Context) -> NSPopUpButton {
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: titles)
        b.target = context.coordinator
        b.action = #selector(Coordinator.changed(_:))
        return b
    }
    func updateNSView(_ b: NSPopUpButton, context: Context) { b.selectItem(at: index); context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject {
        var parent: TestPopUp
        init(parent: TestPopUp) { self.parent = parent }
        @objc func changed(_ b: NSPopUpButton) { parent.index = b.indexOfSelectedItem }
    }
}
