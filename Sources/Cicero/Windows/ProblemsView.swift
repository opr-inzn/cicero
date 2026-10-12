import CiceroCore
import SwiftUI

/// Problems grouped by kind, each with an explanation, its files and what to do about them.
struct ProblemsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = ProblemKind.allCases.compactMap { kind -> (kind: ProblemKind, problems: [Problem])? in
            let problems = model.problems.filter { $0.kind == kind }
            return problems.isEmpty ? nil : (kind, problems)
        }
        Group {
            if groups.isEmpty {
                ContentUnavailableView("No Problems", systemImage: "checkmark.circle",
                                       description: Text(model.hasScanned ? "Cicero found nothing wrong with your fonts." : "Cicero is checking your fonts…"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(groups, id: \.kind) { group in
                            if group.kind.isMinor {
                                MinorProblemGroup(kind: group.kind, problems: group.problems)
                            } else {
                                ProblemGroup(kind: group.kind, problems: group.problems)
                            }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .navigationTitle("Problems")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button("Check Again", systemImage: "arrow.clockwise") { model.rescan() }
                    .disabled(model.scanProgress != nil)
                    .help("Look through the library again")
            }
        }
    }

    private var subtitle: String {
        switch model.problems.count(where: { !$0.kind.isMinor }) {
        case 0: ""
        case 1: "1 problem"
        case let count: "\(count) problems"
        }
    }
}

private struct ProblemGroup: View {
    let kind: ProblemKind
    let problems: [Problem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title).font(.title2.bold())
            Text(kind.explanation).foregroundStyle(.secondary)
            ForEach(problems) { ProblemCard(problem: $0) }
        }
    }
}

/// Minor problems, collapsed until opened.
private struct MinorProblemGroup: View {
    let kind: ProblemKind
    let problems: [Problem]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.explanation).foregroundStyle(.secondary)
                ForEach(problems) { ProblemCard(problem: $0) }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text(kind.title).font(.title3.weight(.semibold))
                Text("\(problems.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

private struct ProblemCard: View {
    let problem: Problem

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(problem.title).font(.headline)
                        Text(problem.summary)
                    }
                    Spacer(minLength: 0)
                    FixButtons(fixes: problem.fixes, kind: problem.kind)
                }
                ForEach(problem.files, id: \.path) { file in
                    Divider()
                    FileRow(file: file, fixes: problem.fileFixes[file.path] ?? [], kind: problem.kind)
                }
            }
            .padding(6)
        }
    }
}

private struct FileRow: View {
    let file: ProblemFile
    let fixes: [ProblemFix]
    let kind: ProblemKind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                Text(((file.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(facts).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FixButtons(fixes: fixes, kind: kind).controlSize(.small)
        }
    }

    private var facts: String {
        var parts: [String] = []
        if let version = file.version { parts.append("Version \(FontFace.displayVersion(version))") }
        if let modified = file.modified { parts.append("Modified \(modified.formatted(date: .abbreviated, time: .omitted))") }
        if !file.detail.isEmpty { parts.append(file.detail) }
        return parts.joined(separator: " · ")
    }
}

private struct FixButtons: View {
    @Environment(AppModel.self) private var model
    let fixes: [ProblemFix]
    let kind: ProblemKind

    var body: some View {
        HStack(spacing: 6) {
            ForEach(fixes, id: \.self) { fix in
                Button(title(fix), role: isDestructive(fix) ? .destructive : nil) { model.apply(fix) }
            }
        }
    }

    /// Only in Installed Twice is a trashed file a spare copy of the same font.
    private func title(_ fix: ProblemFix) -> String {
        if kind == .installedTwice, case .trash(let paths) = fix, paths.count == 1 { return "Remove Copy…" }
        return fix.title
    }

    private func isDestructive(_ fix: ProblemFix) -> Bool {
        if case .trash = fix { return true }
        return false
    }
}
