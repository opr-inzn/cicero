import PointCore
import SwiftUI

/// Asks how to activate when the install method is Ask: copy the files, use them where they are,
/// or only for a while.
struct ActivationSheet: View {
    let prompt: ActivationPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activate \(prompt.title)").font(.title2.bold())
                Text(prompt.faces.count == 1 ? "How should Point turn this font on?" : "How should Point turn these fonts on?")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                option("Install a Copy", icon: "doc.on.doc",
                       detail: "Copies the files into your Fonts folder. The originals stay where they are.") { choose(.copy) }
                option("Use Files Where They Are", icon: "link",
                       detail: "macOS uses the files from where they are. If they move or their disk is unplugged, the fonts stop working.") { choose(.inPlace) }
            }
            Toggle("Remember this choice (you can change it in Settings → General)", isOn: $remember)
            HStack {
                TemporaryMenu { scope in
                    model.activateTemporarily(prompt.faces, scope: scope)
                    dismiss()
                }
                .fixedSize()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 560)
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
        model.performActivation(prompt.faces, method: method)
        dismiss()
    }
}
