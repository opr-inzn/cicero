import CiceroCore
import SwiftUI

/// Asks how to bring in font files the user adds while the install method is Ask: copy them into the Fonts folder and
/// turn them on, move the ones that can move there, or list them where they are, off. Dropped on a location, copying or
/// moving puts them into it instead (see `DropLocation`).
struct InstallSheet: View {
    let prompt: InstallPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold()).lineLimit(1).truncationMode(.middle)
                Text(question).foregroundStyle(.secondary)
            }
            let one = prompt.files.count == 1
            HStack(spacing: 12) {
                if let location = prompt.location {
                    let into = "into “\(location.name)”\(Self.effect(of: location, one: one))"
                    option("Copy Into “\(location.name)”", icon: "doc.on.doc",
                           detail: one ? "Copies the file \(into). The original stays where it is."
                               : "Copies the files \(into). The originals stay where they are.") { choose(.copy) }
                    if prompt.offersMove {
                        option("Move Into “\(location.name)”", icon: "folder",
                               detail: one ? "Moves the file \(into). The folder it was in stays."
                                   : "Moves the files \(into). The folders they were in stay.") { choose(.move) }
                    }
                } else {
                    option("Install a Copy", icon: "doc.on.doc",
                           detail: one ? "Copies the file into \(model.installPlace) and turns it on. The original stays where it is."
                               : "Copies the files into \(model.installPlace) and turns them on. The originals stay where they are.") { choose(.copy) }
                    if prompt.offersMove {
                        option(model.data.installsIntoFontLibrary ? "Move Into Cicero’s Library" : "Move Into Fonts Folder", icon: "folder",
                               detail: one ? "Moves the file into \(model.installPlace) and turns it on. The folder it was in stays."
                                   : "Moves the files into \(model.installPlace) and turns them on. The folders they were in stay.") { choose(.move) }
                    }
                }
                option("Leave Files Where They Are", icon: "link",
                       detail: one ? "Lists the file under Added Fonts, where it is, without turning it on."
                           : "Lists the files under Added Fonts, where they are, without turning them on.") { choose(.inPlace) }
            }
            // Every option as tall as the tallest.
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Toggle("Remember this choice (you can change it later)", isOn: $remember)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: prompt.offersMove ? 720 : 560)
    }

    /// "How should Cicero install this font file?", or add it to the location it was dropped on.
    private var question: String {
        let files = prompt.files.count == 1 ? "this font file" : "these font files"
        guard let location = prompt.location else { return "How should Cicero install \(files)?" }
        return "How should Cicero add \(files) to “\(location.name)”?"
    }

    /// How the files are once in the location: " and turns it on" for an Active one, ", where Adobe apps use it" for one an
    /// app loads by itself, else " without turning it on".
    private static func effect(of location: DropLocation, one: Bool) -> String {
        let it = one ? "it" : "them"
        if location.isActive { return " and turns \(it) on" }
        guard let app = location.app else { return " without turning \(it) on" }
        return app == "Adobe" ? ", where Adobe apps use \(it)" : ", where \(app) uses \(it)"
    }

    /// "Add “Name-Regular.otf”", or "Add 12 Font Files".
    private var title: String {
        prompt.files.count == 1 ? "Add “\(URL(fileURLWithPath: prompt.files[0]).lastPathComponent)”" : "Add \(prompt.files.count) Font Files"
    }

    private func option(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // As tall for every symbol, so the titles line up.
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(height: 36)
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .top)
            .padding(12)
        }
        .buttonStyle(OptionButtonStyle())
    }

    private func choose(_ method: InstallMethod) {
        if remember { model.data.installMethod = method }
        dismiss()
        prompt.add(model, method)
    }
}

/// A card that's as tall as its label. A bordered button sized it on its own, cutting the last line of a long detail
/// off at the bottom on some Macs.
private struct OptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AnyShapeStyle(.fill) : AnyShapeStyle(.fill.secondary), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
    }
}

extension View {
    /// Asks whether to turn on as many families as `AppModel.manyActivationPrompt` holds, when `isActive`: the main window
    /// asks unless a sheet of its own is up, which asks from there.
    func confirmsManyActivations(when isActive: Bool = true) -> some View {
        modifier(ManyActivationConfirmation(isActive: isActive))
            .modifier(MovingOutConfirmation(isActive: isActive))
    }
}

/// Asks whether to turn off fonts whose files would move out of a folder others share (`AppModel.movingOutPrompt`).
private struct MovingOutConfirmation: ViewModifier {
    let isActive: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        // On a view of its own, as the question about turning on many fonts.
        content.background {
            Color.clear
                .alert(
                    model.movingOutPrompt?.title ?? "",
                    isPresented: Binding(get: { isActive && model.movingOutPrompt != nil }, set: { if !$0 { model.movingOutPrompt = nil } }),
                    presenting: model.movingOutPrompt
                ) { prompt in
                    Button("Move and Deactivate") { model.confirm(prompt, movingOut: true) }
                    if let keep = prompt.keepTitle {
                        Button(keep) { model.confirm(prompt, movingOut: false) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { prompt in
                    Text(prompt.message)
                }
                .dialogSuppressionToggle("Don’t ask again", isSuppressed: Binding(
                    get: { !model.data.asksBeforeMovingOutOfSharedFolders },
                    set: { model.data.asksBeforeMovingOutOfSharedFolders = !$0 }
                ))
        }
    }
}

private struct ManyActivationConfirmation: ViewModifier {
    let isActive: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        // On a view of its own, so the window's other alerts don't get the switch.
        content.background {
            Color.clear
                .alert(
                    model.manyActivationPrompt.map { "Activate \($0.families.formatted()) families?" } ?? "",
                    isPresented: Binding(get: { isActive && model.manyActivationPrompt != nil }, set: { if !$0 { model.manyActivationPrompt = nil } }),
                    presenting: model.manyActivationPrompt
                ) { prompt in
                    Button(prompt.temporarily ? "Activate Temporarily" : "Activate") { model.confirm(prompt) }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("Apps load every font that’s on as they open, so this many at once can slow them down.")
                }
                .dialogSuppressionToggle("Don’t ask again", isSuppressed: Binding(
                    get: { !model.data.asksBeforeActivatingMany },
                    set: { model.data.asksBeforeActivatingMany = !$0 }
                ))
        }
    }
}
