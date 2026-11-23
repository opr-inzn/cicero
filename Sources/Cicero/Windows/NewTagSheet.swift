import CiceroCore
import SwiftUI

struct NewTagSheet: View {
    let request: NewTagRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: TagColor?

    init(request: NewTagRequest) {
        self.request = request
        _color = State(initialValue: request.color)
    }

    private var tagName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? color?.title ?? "" : typed
    }

    var body: some View {
        let taken = model.data.tags.contains(tagName)
        VStack(alignment: .leading, spacing: 14) {
            Text("New Tag").font(.title2.bold())
            TextField("Name", text: $name, prompt: Text(color?.title ?? "Name"))
            HStack(spacing: 6) {
                swatch(nil)
                ForEach(TagColor.allCases, id: \.self) { swatch($0) }
            }
            if taken {
                Text("There’s already a tag called “\(tagName)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") {
                    model.addTag(named: tagName, color: color, to: request.families)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagName.isEmpty || taken)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func swatch(_ option: TagColor?) -> some View {
        let picked = option == color
        return Button { color = option } label: {
            ZStack {
                if let option {
                    Circle().fill(option.color)
                } else {
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                    Rectangle().fill(.secondary).frame(width: 1, height: 16).rotationEffect(.degrees(45))
                }
            }
            .frame(width: 18, height: 18)
            .padding(4)
            .overlay {
                if picked { Circle().strokeBorder(option?.color ?? .secondary, lineWidth: 2) }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option?.title ?? "None")
        .accessibilityLabel(option?.title ?? "No Color")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
