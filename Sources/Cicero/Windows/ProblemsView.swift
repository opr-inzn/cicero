import CiceroCore
import SwiftUI

struct ProblemsView: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0
    @State private var marks: [String: Set<String>] = [:]

    var body: some View {
        let groups = ProblemKind.allCases.compactMap { kind -> (kind: ProblemKind, problems: [Problem])? in
            let problems = model.problems.filter { $0.kind == kind }
            return problems.isEmpty ? nil : (kind, problems)
        }
        Group {
            if groups.isEmpty {
                if model.hasScanned {
                    EmptyState("No Conflicts", systemImage: "checkmark.circle",
                               description: Text("Fonts installed twice, duplicates, and missing or damaged files show up here."))
                } else {
                    EmptyState("Checking Fonts…", systemImage: "checkmark.circle",
                               description: Text("Fonts installed twice, duplicates, and missing or damaged files will show up here."))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(groups, id: \.kind) { group in
                            if group.kind == .duplicates {
                                DuplicatesSection(problems: group.problems, marks: $marks)
                            } else if group.kind.isMinor {
                                MinorProblemGroup(kind: group.kind, problems: group.problems)
                            } else {
                                ProblemGroup(kind: group.kind, problems: group.problems)
                            }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    // Centred by the width outside the scroll view: inside it, a scroll bar that takes room moves the centre whenever the list starts to scroll.
                    .padding(.leading, max(0, (width - 808) / 2))
                    // The scroll view is only as wide as its content. Fill the window so it scrolls anywhere and its bar sits at the edge.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let duplicates = groups.first(where: { $0.kind == .duplicates }) {
                        DuplicatesBar(problems: duplicates.problems, marks: $marks)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Color.canvas)
        .navigationTitle("Conflicts")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        switch model.problems.count(where: { !$0.kind.isMinor }) {
        case 0: ""
        case 1: "1 conflict"
        case let count: "\(count.plain) conflicts"
        }
    }
}

private struct ProblemGroup: View {
    @Environment(AppModel.self) private var model
    let kind: ProblemKind
    let problems: [Problem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(kind.title).font(.title2.bold())
                Spacer(minLength: 0)
                let extras = problems.filter { !$0.extraCopies.isEmpty }
                if extras.count > 1 {
                    Button("Move All Extra Copies to Trash", role: .destructive) {
                        model.trashExtraCopies(of: extras)
                    }
                    .help(kind == .installedTwice
                        ? "Keep the newest copy of each font and move the others to the Trash"
                        : "Keep the newest copy of each font in each folder and move the others to the Trash")
                }
                let forgettable = problems.filter { $0.fixes.contains(where: \.isForget) }
                if kind == .missing && forgettable.count > 1 {
                    Button("Forget All") { model.forgetAll(of: forgettable) }
                        .help("Stop looking for these missing files and remove them from your library")
                }
            }
            Text(kind.explanation).foregroundStyle(.secondary)
            ForEach(problems) { ProblemCard(problem: $0) }
        }
    }
}

private extension Problem {
    func marked(_ marks: [String: Set<String>]) -> Set<String> {
        guard let chosen = marks[id] else { return Set(extraCopies) }
        let valid = chosen.intersection(trashable)
        return copyGroups.contains { $0.allSatisfy(valid.contains) } ? Set(extraCopies) : valid
    }
}

private enum DuplicateColumn {
    static let folder: CGFloat = 180
    static let version: CGFloat = 64
    static let modified: CGFloat = 96
}

private struct DuplicatesSection: View {
    let problems: [Problem]
    @Binding var marks: [String: Set<String>]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ProblemKind.duplicates.title).font(.title2.bold())
            Text(ProblemKind.duplicates.explanation).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    separator
                    Text("Folder").frame(width: DuplicateColumn.folder, alignment: .leading)
                    separator
                    Text("Version").frame(width: DuplicateColumn.version, alignment: .leading)
                    separator
                    Text("Modified").frame(width: DuplicateColumn.modified, alignment: .leading)
                }
                .lineLimit(1)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .overlay(alignment: .bottom) { Divider() }
                ForEach(problems) { problem in
                    let marked = problem.marked(marks)
                    HStack(spacing: 6) {
                        Text(problem.title).fontWeight(.semibold)
                        Text(problem.files.count == 1 ? "1 file" : "\(problem.files.count.plain) files").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 5)
                    ForEach(Array(problem.files.enumerated()), id: \.element.path) { index, file in
                        DuplicateRow(file: file, problem: problem, marked: marked, isStriped: !index.isMultiple(of: 2), marks: $marks)
                    }
                }
            }
        }
    }
}

private extension DuplicatesSection {
    var separator: some View {
        Rectangle().fill(.separator).frame(width: 1, height: 16).frame(width: 12)
    }
}

private struct DuplicateRow: View {
    @Environment(AppModel.self) private var model
    let file: ProblemFile
    let problem: Problem
    let marked: Set<String>
    let isStriped: Bool
    @Binding var marks: [String: Set<String>]

    var body: some View {
        let isMarked = marked.contains(file.path)
        let blocker = isMarked ? nil : blocker
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isMarked }, set: { toggle($0) })) {
                Text((file.path as NSString).lastPathComponent)
                    .strikethrough(isMarked)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .toggleStyle(.checkbox)
            .disabled(blocker != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(((file.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: DuplicateColumn.folder, alignment: .leading)
            Text(file.version.map(FontFace.displayVersion) ?? "")
                .frame(width: DuplicateColumn.version, alignment: .leading)
            Text(file.modified?.formatted(date: .abbreviated, time: .omitted) ?? "")
                .frame(width: DuplicateColumn.modified, alignment: .leading)
        }
        .foregroundStyle(isMarked ? .secondary : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isStriped ? Color.primary.opacity(0.035) : .clear, in: .rect(cornerRadius: 5))
        .help(blocker ?? "")
        .contextMenu {
            Button("Show in Finder") { model.apply(.reveal([file.path]), family: problem.family) }
        }
    }

    private var blocker: String? {
        problem.trashable.contains(file.path) ? nil : "This file also holds a font that has no other copy."
    }

    private func toggle(_ isOn: Bool) {
        var set = marked
        guard isOn else {
            set.remove(file.path)
            marks[problem.id] = set
            return
        }
        set.insert(file.path)
        for group in problem.copyGroups where group.contains(file.path) && group.allSatisfy(set.contains) {
            if let other = group.first(where: { $0 != file.path }) { set.remove(other) }
        }
        marks[problem.id] = set
    }
}

private struct DuplicatesBar: View {
    @Environment(AppModel.self) private var model
    let problems: [Problem]
    @Binding var marks: [String: Set<String>]

    var body: some View {
        let paths = problems.flatMap { $0.marked(marks).sorted() }
        HStack(spacing: 12) {
            Text(paths.isEmpty ? "No duplicates selected."
                : paths.count == 1 ? "1 duplicate file will go to the Trash." : "\(paths.count.plain) duplicate files will go to the Trash.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !paths.isEmpty {
                Button("Deselect All") { marks = Dictionary(uniqueKeysWithValues: problems.map { ($0.id, []) }) }
            } else if problems.contains(where: { !$0.extraCopies.isEmpty }) {
                Button("Select Extra Copies") { marks = [:] }
            }
            Button(paths.isEmpty ? "Move to Trash" : paths.count == 1 ? "Move 1 File to Trash" : "Move \(paths.count.plain) Files to Trash") {
                model.trashExtraCopies(of: problems.filter { !$0.marked(marks).isEmpty }, paths: paths)
            }
            .buttonStyle(.borderedProminent)
            .disabled(paths.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct MinorProblemGroup: View {
    let kind: ProblemKind
    let problems: [Problem]
    @State private var isExpanded = true

    var body: some View {
        // DisclosureGroup animates opening but not closing. Open instantly too.
        DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { newValue in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { isExpanded = newValue }
        })) {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.explanation).foregroundStyle(.secondary)
                ForEach(problems) { ProblemCard(problem: $0) }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text(kind.title).font(.title3.weight(.semibold))
                Text(problems.count.plain).foregroundStyle(.secondary).monospacedDigit()
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
                    FixButtons(fixes: problem.fixes, kind: problem.kind, family: problem.family)
                }
                if problem.kind.groupsFilesByFolder {
                    ForEach(problem.folders, id: \.path) { folder in
                        Divider()
                        let isNewest = folder.path == problem.newestFolder
                        if folder.files.count == 1 {
                            FileRow(file: folder.files[0], fixes: problem.fileFixes[folder.files[0].path] ?? [], kind: problem.kind, family: problem.family, isNewest: isNewest)
                        } else {
                            FolderRow(folder: folder, fixes: problem.folderFixes[folder.path] ?? [], fileFixes: problem.fileFixes, kind: problem.kind, family: problem.family, isNewest: isNewest)
                        }
                    }
                } else {
                    ForEach(problem.files, id: \.path) { file in
                        Divider()
                        FileRow(file: file, fixes: problem.fileFixes[file.path] ?? [], kind: problem.kind, family: problem.family)
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
    var family: String?
    var isNewest = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.title ?? (file.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if isNewest { NewestTag() }
                    if !file.preferredFor.isEmpty && file.preferredStyles == nil { PreferredTag(names: file.preferredFor) }
                }
                Text(((file.title == nil ? (file.path as NSString).deletingLastPathComponent : file.path) as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .truncationMode(.middle)
                Text(Self.facts(of: file)).font(.caption).foregroundStyle(.secondary)
                if let styles = file.preferredStyles {
                    Text("Preferred for \(styles)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(PreferredTag.help(file.preferredFor))
                }
            }
            Spacer(minLength: 0)
            FixButtons(fixes: fixes, kind: kind, family: family).controlSize(.small)
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

private struct FolderRow: View {
    let folder: ProblemFolder
    let fixes: [ProblemFix]
    let fileFixes: [String: [ProblemFix]]
    let kind: ProblemKind
    let family: String?
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
                            .truncationMode(.middle)
                        if isNewest { NewestTag() }
                    }
                    Text(facts).font(.caption).foregroundStyle(.secondary)
                    Button {
                        isExpanded.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            Text("\(folder.files.count.plain) files")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(isExpanded ? "Hide Files" : "Show \(folder.files.count.plain) Files")
                }
                Spacer(minLength: 0)
                FixButtons(fixes: fixes, kind: kind, family: family).controlSize(.small)
            }
            if isExpanded {
                let filesDiffer = self.filesDiffer
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(folder.files, id: \.path) { file in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text((file.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                                if filesDiffer {
                                    Text(FileRow.facts(of: file)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            FixButtons(fixes: fileFixes[file.path] ?? [], kind: kind, family: family).controlSize(.small)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private var facts: String {
        var parts: [String] = []
        let versions = unique(folder.files.compactMap { $0.version.map(FontFace.displayVersion) })
        switch versions.count {
        case 0: break
        case 1: parts.append("Version \(versions[0])")
        case 2: parts.append("Versions \(versions[0]) and \(versions[1])")
        default: parts.append("\(versions.count.plain) versions")
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
        Tag(text: "Preferred", tint: .blue).help(Self.help(names))
    }

    static func help(_ names: [String]) -> String {
        "Apps that ask for \(names.listed()) get this font."
    }
}

private struct FixButtons: View {
    @Environment(AppModel.self) private var model
    let fixes: [ProblemFix]
    let kind: ProblemKind
    let family: String?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(fixes, id: \.self) { fix in
                Button(title(fix), role: isDestructive(fix) ? .destructive : nil) { model.apply(fix, family: family) }
                    .help(help(fix))
            }
        }
    }

    private func title(_ fix: ProblemFix) -> String {
        if kind == .installedTwice, case .trash(let paths) = fix { return paths.count == 1 ? "Move Copy to Trash" : "Move Copies to Trash" }
        return fix.title
    }

    private func help(_ fix: ProblemFix) -> String {
        guard case .removeFromAdobeFonts = fix else { return "" }
        return "Open this family’s page on Adobe Fonts to remove it; Creative Cloud will then remove its copy"
    }

    private func isDestructive(_ fix: ProblemFix) -> Bool {
        if case .trash = fix { return true }
        return false
    }
}
