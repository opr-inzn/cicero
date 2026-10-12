import AppKit
import SwiftUI

/// Everything ProblemFinder found, grouped by kind, each with a plain explanation and its fixes.
struct ProblemsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var trashRequest: TrashRequest?

    private struct TrashRequest: Identifiable {
        let id = UUID()
        var title: String
        var message: String
        var paths: [String] = []
        var keep: String?
        /// A conflicting copy to deactivate instead of trashing paths directly; the store decides whether
        /// it goes to the Trash or to the Deactivated folder.
        var face: LibraryFace?
    }

    private struct ProblemGroup: Identifiable {
        var kind: ProblemKind
        var problems: [FontProblem]
        var id: ProblemKind { kind }
    }

    var body: some View {
        let groups = ProblemKind.allCases.compactMap { kind -> ProblemGroup? in
            let items = library.problems.filter { $0.kind == kind }
            return items.isEmpty ? nil : ProblemGroup(kind: kind, problems: items)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(groups) { section($0) }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.canvas)
        .overlay {
            if library.problems.isEmpty && library.hasScanned {
                ContentUnavailableView("No Problems", systemImage: "checkmark.circle",
                                       description: Text("Your fonts are in good shape."))
            }
        }
        .navigationTitle("Problems")
        .navigationSubtitle(library.problemsLabel)
        .toolbar {
            ToolbarItem {
                Button { library.rescan() } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                    .help("Scan the library again")
                    .disabled(library.isScanning)
            }
        }
        .task { library.refreshProblems() }
        .alert(
            trashRequest?.title ?? "",
            isPresented: Binding(get: { trashRequest != nil }, set: { if !$0 { trashRequest = nil } }),
            presenting: trashRequest
        ) { request in
            Button(request.face == nil ? "Move to Trash" : "Remove", role: .destructive) { perform(request) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }

    private func perform(_ request: TrashRequest) {
        if let face = request.face {
            Task { await library.deactivate([face]) }
        } else {
            library.trashFiles(request.paths, keeping: request.keep)
        }
    }

    // MARK: Sections and cards

    private func section(_ group: ProblemGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: group.kind.icon)
                    .foregroundStyle(tint(group.kind))
                Text(group.kind.title)
                    .font(.title3.weight(.semibold))
                Text(group.problems.count, format: .number)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(group.kind.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(group.problems) { card($0) }
        }
    }

    private func tint(_ kind: ProblemKind) -> Color {
        switch kind {
        case .conflict, .unreadable: .red
        case .missing, .external: .orange
        case .duplicate: .secondary
        }
    }

    private func card(_ problem: FontProblem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title).font(.headline)
                Text(problem.summary).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(problem.files) { fileRow($0, in: problem) }
            HStack(spacing: 8) { actions(for: problem) }
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func fileRow(_ file: ProblemFile, in problem: FontProblem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayPath)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(details(of: file, in: problem))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { fileActions(file, in: problem) }
                .controlSize(.small)
        }
    }

    private func details(of file: ProblemFile, in problem: FontProblem) -> String {
        var parts: [String] = []
        if let version = file.version { parts.append("Version \(version)") }
        if let modified = file.modified { parts.append("Modified \(modified.formatted(date: .abbreviated, time: .omitted))") }
        parts.append(file.note)
        if case .duplicate(let keep) = problem.detail, keep == file.path { parts.append("This copy stays") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    @ViewBuilder
    private func fileActions(_ file: ProblemFile, in problem: FontProblem) -> some View {
        if file.exists {
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) }
        }
        if case .conflict(let template) = problem.detail, file.isUserControllable {
            let face = library.conflictFace(at: file.path, template: template, others: problem.files.map(\.path))
            if file.activeKind == .user {
                Button("Remove Copy…") {
                    trashRequest = TrashRequest(
                        title: "Remove this copy?",
                        message: "Point moves \(file.displayPath) to the Trash, or to its Deactivated folder if it's your only copy outside the Fonts folder. The other copy stays active.",
                        face: face
                    )
                }
            } else {
                Button("Deactivate") { Task { await library.deactivate([face]) } }
            }
        }
    }

    @ViewBuilder
    private func actions(for problem: FontProblem) -> some View {
        switch problem.detail {
        case .conflict:
            EmptyView()
        case .duplicate(let keep):
            let extras = problem.files.map(\.path).filter { $0 != keep && library.mayTrash($0) }
            if !extras.isEmpty {
                Button(extras.count == 1 ? "Move Extra Copy to Trash…" : "Move \(extras.count) Extra Copies to Trash…") {
                    trashRequest = TrashRequest(
                        title: extras.count == 1 ? "Move the extra copy to the Trash?" : "Move \(extras.count) extra copies to the Trash?",
                        message: "The copy at \((keep as NSString).abbreviatingWithTildeInPath) stays.",
                        paths: extras, keep: keep
                    )
                }
            }
        case .missingRegistered(let path):
            Button("Forget") { library.forgetRegistration(path) }
        case .missingInstalledCopy(let path, _):
            Button("Forget") { library.forgetInstalledCopy(path) }
        case .missingSetMember(let setID, let name):
            Button("Remove from Set") { library.removeMember(name, fromSet: setID) }
        case .unreadable(let path):
            if library.mayTrash(path) {
                Button("Move to Trash…") {
                    trashRequest = TrashRequest(title: "Move this file to the Trash?", message: (path as NSString).abbreviatingWithTildeInPath, paths: [path])
                }
            }
        case .external(let face):
            Button("Install a Copy Instead") { Task { await library.installCopyInstead(of: face) } }
                .help("Copies the file into ~/Library/Fonts and stops using the one on the disk")
            Button("Deactivate") { Task { await library.deactivate([face]) } }
        }
    }
}
