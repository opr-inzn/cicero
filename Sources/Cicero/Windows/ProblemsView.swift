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
                if problem.kind.groupsFilesByFolder {
                    ForEach(problem.folders, id: \.path) { folder in
                        Divider()
                        let isNewest = folder.path == problem.newestFolder
                        if folder.files.count == 1 {
                            FileRow(file: folder.files[0], fixes: problem.fileFixes[folder.files[0].path] ?? [], kind: problem.kind, isNewest: isNewest)
                        } else {
                            FolderRow(folder: folder, fixes: problem.folderFixes[folder.path] ?? [], fileFixes: problem.fileFixes, kind: problem.kind, isNewest: isNewest)
                        }
                    }
                } else {
                    ForEach(problem.files, id: \.path) { file in
                        Divider()
                        FileRow(file: file, fixes: problem.fileFixes[file.path] ?? [], kind: problem.kind)
                    }
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
    var isNewest = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.title ?? (file.path as NSString).lastPathComponent).lineLimit(1)
                    if isNewest { NewestTag() }
                    if !file.preferredFor.isEmpty { PreferredTag(names: file.preferredFor) }
                }
                // Under a title, the whole path says which file it is.
                Text(((file.title == nil ? (file.path as NSString).deletingLastPathComponent : file.path) as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.facts(of: file)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FixButtons(fixes: fixes, kind: kind).controlSize(.small)
        }
    }

    static func facts(of file: ProblemFile) -> String {
        var parts = file.note.map { [$0] } ?? []
        if let version = file.version { parts.append("Version \(FontFace.displayVersion(version))") }
        if let modified = file.modified { parts.append("Modified \(modified.formatted(date: .abbreviated, time: .omitted))") }
        if !file.detail.isEmpty { parts.append(file.detail) }
        return parts.joined(separator: " · ")
    }
}

/// Several files in one folder, usually one copy of a whole family: one row for all of them, with the files
/// themselves under a disclosure.
private struct FolderRow: View {
    let folder: ProblemFolder
    let fixes: [ProblemFix]
    let fileFixes: [String: [ProblemFix]]
    let kind: ProblemKind
    let isNewest: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text((folder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isNewest { NewestTag() }
                    }
                    Text(facts).font(.caption).foregroundStyle(.secondary)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            Text("\(folder.files.count) files")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(isExpanded ? "Hide Files" : "Show \(folder.files.count) Files")
                }
                Spacer(minLength: 0)
                FixButtons(fixes: fixes, kind: kind).controlSize(.small)
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(folder.files, id: \.path) { file in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                                if filesDiffer {
                                    Text(FileRow.facts(of: file)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            FixButtons(fixes: fileFixes[file.path] ?? [], kind: kind).controlSize(.small)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    /// What the files have in common, or the range when they don't.
    private var facts: String {
        var parts: [String] = []
        let versions = unique(folder.files.compactMap { $0.version.map(FontFace.displayVersion) })
        switch versions.count {
        case 0: break
        case 1: parts.append("Version \(versions[0])")
        case 2: parts.append("Versions \(versions[0]) and \(versions[1])")
        default: parts.append("\(versions.count) versions")
        }
        let dates = folder.files.compactMap(\.modified)
        if let first = dates.min(), let last = dates.max() {
            parts.append(Calendar.current.isDate(first, inSameDayAs: last)
                ? "Modified \(first.formatted(date: .abbreviated, time: .omitted))"
                : "Modified \((first..<last).formatted(date: .abbreviated, time: .omitted))")
        }
        parts += unique(folder.files.map(\.detail).filter { !$0.isEmpty })
        return parts.joined(separator: " · ")
    }

    /// Whether each file needs its own version, date and place.
    private var filesDiffer: Bool {
        Set(folder.files.map(FileRow.facts)).count > 1
    }

    private func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

private struct NewestTag: View {
    var body: some View {
        Tag(text: "Newest", tint: .green).help("The highest version. Usually the copy to keep.")
    }
}

private struct PreferredTag: View {
    let names: [String]

    var body: some View {
        Tag(text: "Preferred", tint: .blue).help("Apps that ask for \(ListFormatter.localizedString(byJoining: names)) get this font.")
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
        if kind == .installedTwice, case .trash(let paths) = fix { return paths.count == 1 ? "Remove Copy…" : "Remove Copies…" }
        return fix.title
    }

    private func isDestructive(_ fix: ProblemFix) -> Bool {
        if case .trash = fix { return true }
        return false
    }
}
