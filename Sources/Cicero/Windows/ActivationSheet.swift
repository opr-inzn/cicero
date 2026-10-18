import CiceroCore
import SwiftUI

/// Asks how to activate when the install method is Ask: copy the files, move the ones added one at a time,
/// leave them where they are, or only for a while.
struct ActivationSheet: View {
    let prompt: ActivationPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activate \(prompt.title)").font(.title2.bold())
                Text(prompt.faces.count == 1 ? "How should Cicero turn this font on?" : "How should Cicero turn these fonts on?")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                option("Install a Copy", icon: "doc.on.doc",
                       detail: "Copies the files into your Fonts folder. The originals stay where they are.") { choose(.copy) }
                if offersMove {
                    option("Move Into Fonts Folder", icon: "folder",
                           detail: "Moves the files you added into your Fonts folder. The folders they were in stay.") { choose(.move) }
                }
                option("Leave Files Where They Are", icon: "link",
                       detail: "macOS uses the files from where they are. If they move or their disk is unplugged, the fonts stop working.") { choose(.inPlace) }
            }
            Toggle("Remember this choice (you can change it in Settings → General)", isOn: $remember)
            HStack {
                if prompt.switching == nil && prompt.faces.contains(where: \.canActivateTemporarily) {
                    Button("Activate Temporarily") {
                        model.activateTemporarily(prompt.faces, confirmed: true)
                        dismiss()
                    }
                    .help(prompt.faces.count == 1 ? "Turns the font on until Cicero quits." : "Turns the fonts on until Cicero quits.")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: offersMove ? 720 : 560)
    }

    /// Some of the files were added one at a time, so they can move (see `AppModel.movableFiles`).
    private var offersMove: Bool {
        prompt.switching == nil && !model.movableFiles(among: prompt.faces.map(\.face.path)).isEmpty
    }

    private func option(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
    }

    private func choose(_ method: InstallMethod) {
        if remember { model.data.installMethod = method }
        if let switching = prompt.switching {
            model.performCopySwitch(switching, method: method)
        } else {
            model.performActivation(prompt.faces, method: method)
        }
        dismiss()
    }
}

extension View {
    /// Asks whether to turn on as many families as `AppModel.manyActivationPrompt` holds, when `isActive`: the main window
    /// asks unless a sheet of its own is up, which asks from there.
    func confirmsManyActivations(when isActive: Bool = true) -> some View {
        modifier(ManyActivationConfirmation(isActive: isActive))
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
                    Text("Apps list every font that’s on in their font menus, and so many at once can make them slower to open.")
                }
                .dialogSuppressionToggle("Don’t ask again", isSuppressed: Binding(
                    get: { !model.data.asksBeforeActivatingMany },
                    set: { model.data.asksBeforeActivatingMany = !$0 }
                ))
        }
    }
}
