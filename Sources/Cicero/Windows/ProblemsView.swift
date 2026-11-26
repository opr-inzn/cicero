import CiceroCore
import SwiftUI

struct ProblemsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("conflicts.widths") private var savedWidths = ""
    @State private var marks: [String: Bool] = [:]
    @State private var visibleWidth: CGFloat = 900
    @State private var headerTop: CGFloat = 100
    @State private var solidTop = false
    @State private var dragWidths: [ConflictColumn: CGFloat]?
    @State private var resizing: (column: ConflictColumn, start: [ConflictColumn: CGFloat])?
    @FocusState private var focused: Bool

    var body: some View {
        let query = model.appliedSearch.trimmingCharacters(in: .whitespaces)
        let shown = Self.filtered(model.problems, by: query)
        let groups = ProblemKind.allCases.compactMap { kind -> (kind: ProblemKind, problems: [Problem])? in
            guard kind != .duplicates else { return nil }
            let problems = shown.filter { $0.kind == kind || kind == .installedTwice && $0.kind == .duplicates }
            return problems.isEmpty ? nil : (kind, problems)
        }
        let trashing = shown.filter { $0.kind.trashesFromTable && !$0.trashable.isEmpty }
        let marked = TrashSelection.marked(in: trashing, overrides: marks)
        Group {
            if groups.isEmpty {
                if !query.isEmpty && !model.problems.isEmpty {
                    EmptyState.search(text: query)
                } else if model.hasScanned {
                    EmptyState("No Conflicts", systemImage: "checkmark.circle",
                               description: Text("Extra copies, missing files, and\ndamaged fonts appear here."))
                } else {
                    EmptyState("Checking Fonts…", systemImage: "checkmark.circle",
                               description: Text("Extra copies, missing files, and\ndamaged fonts will appear here."))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(groups, id: \.kind) { group in
                            let isFirst = group.kind == groups.first?.kind
                            GroupHeading(kind: group.kind, problems: group.problems, isFirst: isFirst)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if isFirst { headerTop = $0 } }
                            let lines = ConflictLine.lines(of: group.problems)
                            let natural = Self.naturalWidths(of: lines)
                            let widths = fitted(self.widths(natural: natural), actions: FixButtons.width(of: lines), natural: natural)
                            Section {
                                ForEach(lines) { line in
                                    switch line.content {
                                    case .heading(let problem):
                                        FamilyHeading(problem: problem)
                                    case .row(let row, let isStriped):
                                        ConflictRowView(row: row, widths: widths, trashing: trashing, marked: marked, isStriped: isStriped, marks: $marks)
                                    }
                                }
                            } header: {
                                header(widths: widths).background(Color.canvas)
                            }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 48)
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width - $0.contentInsets.leading - $0.contentInsets.trailing } action: { _, width in
                    if width > 0 { visibleWidth = width }
                }
                .onScrollGeometryChange(for: Bool.self) { [headerTop] in $0.contentOffset.y + $0.contentInsets.top >= headerTop } action: { solidTop = $1 }
                .hardTopScrollEdge(solidTop)
                .overlay(alignment: .top) {
                    if solidTop {
                        Color.canvas.frame(height: 2).background(Color.canvas.ignoresSafeArea(edges: .top))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !trashing.isEmpty {
                        TrashBar(problems: trashing, marked: marked, marks: $marks)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A focusable view behind the page, or SwiftUI hands the cursor of the list it replaces to the toolbar's search field. Not the page itself, which hands it on to its first checkbox.
        .background {
            Color.canvas
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .modifier(TakesStartFocus(focused: $focused))
        }
        .navigationTitle("Conflicts")
        .navigationSubtitle(subtitle)
    }

    private static func filtered(_ problems: [Problem], by query: String) -> [Problem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return problems }
        func matches(_ texts: [String]) -> Bool {
            words.allSatisfy { word in texts.contains { $0.localizedStandardContains(word) } }
        }
        return problems.compactMap { problem in
            guard !problem.files.isEmpty else { return matches([problem.title]) ? problem : nil }
            var problem = problem
            problem.files = problem.files.filter { matches([problem.title, $0.path, $0.title ?? ""]) }
            return problem.files.isEmpty ? nil : problem
        }
    }

    private var subtitle: String {
        switch model.problems.count(where: { !$0.kind.isMinor }) {
        case 0: ""
        case 1: "1 conflict"
        case let count: "\(count.plain) conflicts"
        }
    }

    // MARK: Columns

    private var saved: [ConflictColumn: CGFloat] {
        var widths: [ConflictColumn: CGFloat] = [:]
        for entry in savedWidths.split(separator: ",") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let column = ConflictColumn(rawValue: String(parts[0])), ConflictColumn.resizable.contains(column), let width = Double(parts[1]) {
                widths[column] = max(column.minimumWidth, width)
            }
        }
        return widths
    }

    private func widths(natural: [ConflictColumn: CGFloat]) -> [ConflictColumn: CGFloat] {
        var widths: [ConflictColumn: CGFloat] = [:]
        for column in ConflictColumn.resizable { widths[column] = natural[column].map { min(column.widestNatural, $0) } ?? column.defaultWidth }
        for (column, width) in saved { widths[column] = width }
        for (column, width) in dragWidths ?? [:] where ConflictColumn.resizable.contains(column) { widths[column] = max(column.minimumWidth, width) }
        return widths
    }

    private static func naturalWidths(of lines: [ConflictLine]) -> [ConflictColumn: CGFloat] {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let header = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        var widths: [ConflictColumn: CGFloat] = [:]
        for column in ConflictColumn.resizable { widths[column] = width(column.title, header) }
        var name: CGFloat = 0
        for line in lines {
            guard case .row(let row, _) = line.content else { continue }
            for column in ConflictColumn.resizable { widths[column] = max(widths[column]!, width(row.text(of: column), font)) }
            var extra: CGFloat = row.problem.kind.trashesFromTable ? 22 : 0
            if row.isNewest { extra += 62 }
            if !row.preferredFor.isEmpty { extra += 72 }
            name = max(name, width(row.name, font) + extra)
        }
        for column in ConflictColumn.resizable {
            widths[column] = max(column.minimumWidth, (widths[column]! + 6).rounded(.up))
        }
        widths[.name] = (name + 6).rounded(.up)
        return widths
    }

    private func fitted(_ widths: [ConflictColumn: CGFloat], actions: CGFloat, natural: [ConflictColumn: CGFloat]) -> [ConflictColumn: CGFloat] {
        var widths = widths
        let name = natural[.name] ?? 0
        widths[.actions] = actions
        let gaps = CGFloat(ConflictColumn.resizable.count) * ConflictColumn.spacing + 2 * ConflictColumn.inset + actions
        var over = gaps + max(ConflictColumn.name.minimumWidth, name) + ConflictColumn.resizable.reduce(0) { $0 + widths[$1]! } - visibleWidth
        for column in [ConflictColumn.folder, .details, .modified, .version] where over > 0 {
            let taken = min(over, widths[column]! - column.minimumWidth)
            widths[column]! -= taken
            over -= taken
        }
        var spare = visibleWidth - gaps - max(ConflictColumn.name.minimumWidth, name) - ConflictColumn.resizable.reduce(0) { $0 + widths[$1]! }
        let saved = saved
        for column in [ConflictColumn.folder, .details] where spare > 0 && saved[column] == nil {
            let grown = min(spare, max(0, (natural[column] ?? 0) - widths[column]!))
            widths[column]! += grown
            spare -= grown
        }
        widths[.name] = max(ConflictColumn.name.minimumWidth, visibleWidth - gaps - ConflictColumn.resizable.reduce(0) { $0 + widths[$1]! })
        return widths
    }

    private func header(widths: [ConflictColumn: CGFloat]) -> some View {
        HStack(spacing: 0) {
            Text(ConflictColumn.name.title).frame(width: widths[.name], alignment: .leading)
            ForEach(ConflictColumn.resizable, id: \.self) { column in
                ColumnDivider(resize: { resize(column, by: -$0, widths: widths) }, endResize: endResize, fit: {})
                Text(column.title).frame(width: widths[column], alignment: .leading)
            }
            Color.clear.frame(width: widths[.actions] ?? 0, height: 1)
        }
        .lineLimit(1)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, ConflictColumn.inset)
        .frame(height: 28)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, ListRowBackground.inset) }
        .padding(.top, 8)
    }

    private func resize(_ column: ConflictColumn, by change: CGFloat, widths: [ConflictColumn: CGFloat]) {
        if resizing?.column != column {
            dragWidths = widths
            resizing = (column, widths)
        }
        guard let start = resizing?.start else { return }
        let room = max(0, (start[.name] ?? 0) - ConflictColumn.name.minimumWidth)
        var next = dragWidths ?? start
        next[column] = max(column.minimumWidth, ((start[column] ?? column.minimumWidth) + min(change, room)).rounded())
        dragWidths = next
    }

    private func endResize() {
        if let dragWidths, let column = resizing?.column, let width = dragWidths[column] {
            var widths = saved
            widths[column] = max(column.minimumWidth, width.rounded())
            let text = ConflictColumn.resizable.compactMap { column in widths[column].map { "\(column.rawValue):\(Int($0))" } }.joined(separator: ",")
            if text != savedWidths { savedWidths = text }
        }
        dragWidths = nil
        resizing = nil
    }
}

private enum ConflictColumn: String, Hashable {
    case name, folder, version, modified, details, actions

    static let resizable: [ConflictColumn] = [.folder, .version, .modified, .details]
    static let spacing: CGFloat = 12
    static let inset = ListRowBackground.contentInset

    var title: String {
        switch self {
        case .name: "Name"
        case .folder: "Path"
        case .version: "Version"
        case .modified: "Modified"
        case .details: "Details"
        case .actions: ""
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name, .actions: 0
        case .folder: 280
        case .version: 70
        case .modified: 100
        case .details: 240
        }
    }

    var widestNatural: CGFloat {
        switch self {
        case .folder: 420
        case .details: 380
        default: 140
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .name: 200
        case .actions: 0
        case .folder: 80
        case .version: 50
        case .modified: 70
        case .details: 80
        }
    }
}

private extension ProblemKind {
    var groupTitle: String { self == .installedTwice ? "Extra Copies" : title }

    var groupExplanation: String {
        guard self == .installedTwice else { return explanation }
        return "The same font is in more than one file. If more than one copy is active, macOS uses only one, so apps may get an older version. You can move selected files to the Trash, and Cicero always keeps at least one copy of each font."
    }

    var trashesFromTable: Bool { self == .installedTwice || self == .duplicates || self == .unreadable }

    var listsFilesUnderTitle: Bool { self == .installedTwice || self == .duplicates || self == .sharedNames }
}

private extension ProblemFix {
    var isReveal: Bool {
        if case .reveal = self { return true }
        return false
    }

    func isRowButton(in kind: ProblemKind) -> Bool {
        switch self {
        case .reveal, .trash: false
        case .deactivate: kind != .installedTwice
        default: true
        }
    }
}

private struct ConflictRow: Identifiable {
    var id: String
    var name: String
    var path: String?
    var folder: String
    var version: String?
    var modified: Date?
    var details = ""
    var fixes: [ProblemFix]
    var canReveal: Bool
    var isNewest = false
    var preferredFor: [String] = []
    var problem: Problem

    func text(of column: ConflictColumn) -> String {
        switch column {
        case .name: name
        case .folder: folder
        case .version: version.map(FontFace.displayVersion) ?? ""
        case .modified: modified?.formatted(date: .abbreviated, time: .omitted) ?? ""
        case .details: details
        case .actions: ""
        }
    }

    static func rows(of problem: Problem) -> [ConflictRow] {
        if problem.kind.listsFilesUnderTitle {
            return problem.files.map { file in
                let fixes = problem.fileFixes[file.path] ?? []
                var details = file.detail
                if problem.kind == .sharedNames { details = file.preferredStyles.map { "Preferred for \($0)" } ?? file.note ?? "" }
                return ConflictRow(
                    id: file.path, name: (file.path as NSString).lastPathComponent, path: file.path, folder: folder(of: file.path),
                    version: file.version, modified: file.modified, details: details,
                    fixes: fixes.filter { $0.isRowButton(in: problem.kind) }, canReveal: fixes.contains(where: \.isReveal),
                    isNewest: problem.newest.contains(file.path),
                    preferredFor: file.preferredStyles == nil ? file.preferredFor : [], problem: problem
                )
            }
        }
        let file = problem.files.first
        let summary = problem.summary.hasSuffix(".") ? String(problem.summary.dropLast()) : problem.summary
        return [ConflictRow(
            id: problem.id, name: file.map { ($0.path as NSString).lastPathComponent } ?? problem.title, path: file?.path,
            folder: file.map { folder(of: $0.path) } ?? "", version: file?.version, modified: file?.modified,
            details: problem.kind == .unreadable ? file?.detail ?? "" : summary,
            fixes: problem.fixes.filter { $0.isRowButton(in: problem.kind) }, canReveal: problem.fixes.contains(where: \.isReveal), problem: problem
        )]
    }

    private static func folder(of path: String) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }
}

private struct ConflictLine: Identifiable {
    enum Content {
        case heading(Problem)
        case row(ConflictRow, isStriped: Bool)
    }

    var id: String
    var content: Content

    static func lines(of problems: [Problem]) -> [ConflictLine] {
        var lines: [ConflictLine] = []
        var index = 0
        for problem in problems {
            if problem.kind.listsFilesUnderTitle {
                lines.append(ConflictLine(id: "heading." + problem.id, content: .heading(problem)))
                index = 0
            }
            for row in ConflictRow.rows(of: problem) {
                lines.append(ConflictLine(id: problem.id + "." + row.id, content: .row(row, isStriped: !index.isMultiple(of: 2))))
                index += 1
            }
        }
        return lines
    }
}

private struct GroupHeading: View {
    @Environment(AppModel.self) private var model
    let kind: ProblemKind
    let problems: [Problem]
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Text(kind.groupTitle)
                    .font(.title2.bold())
                    .alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] - NSFont.preferredFont(forTextStyle: .title2).capHeight / 2 }
                Spacer(minLength: 0)
                let forgettable = problems.filter { $0.fixes.contains(where: \.isForget) }
                if kind == .missing && forgettable.count > 1 {
                    Button("Forget All") { model.forgetAll(of: forgettable) }
                        .help("Clear Cicero’s record of all missing files and remove missing families from your folders.")
                }
            }
            Text(kind.groupExplanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.balancedWidth(of: kind.groupExplanation, upTo: 720), alignment: .leading)
        }
        .padding(.horizontal, ConflictColumn.inset)
        .padding(.top, isFirst ? 24 : 56)
        .padding(.bottom, 4)
    }
}

private extension GroupHeading {
    static func balancedWidth(of text: String, upTo widest: CGFloat) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        func lines(at width: CGFloat) -> Int {
            let height = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
            return Int((height / lineHeight).rounded())
        }
        let target = lines(at: widest)
        guard target > 1 else { return widest }
        var width = (attributed.size().width / CGFloat(target)).rounded(.up)
        while width < widest && lines(at: width) > target { width += 4 }
        return min(widest, width + 4)
    }
}

private struct FamilyHeading: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(problem.title).fontWeight(.semibold)
                if problem.kind != .installedTwice {
                    Text(heading).foregroundStyle(.secondary)
                }
            }
            if problem.kind == .sharedNames {
                Text(problem.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, ConflictColumn.inset)
        .padding(.top, 14)
        .padding(.bottom, 5)
    }

    private var heading: String {
        if problem.kind != .sharedNames, problem.summary.hasSuffix(".") { return String(problem.summary.dropLast()) }
        return problem.files.count == 1 ? "1 file" : "\(problem.files.count.plain) files"
    }
}

private enum TrashSelection {
    static func marked(in problems: [Problem], overrides: [String: Bool]) -> Set<String> {
        let trashable = problems.reduce(into: Set<String>()) { $0.formUnion($1.trashable) }
        let defaults = problems.reduce(into: Set<String>()) { $0.formUnion($1.extraCopies) }
        var result = Set<String>()
        for problem in problems {
            for file in problem.files where trashable.contains(file.path) {
                if overrides[file.path] ?? defaults.contains(file.path) {
                    result.insert(file.path)
                }
            }
        }
        for group in problems.flatMap(\.copyGroups) where !group.isEmpty && group.allSatisfy(result.contains) {
            let keep = group.first { !defaults.contains($0) } ?? group[0]
            result.remove(keep)
        }
        return result
    }
}

private struct ConflictRowView: View {
    @Environment(AppModel.self) private var model
    let row: ConflictRow
    let widths: [ConflictColumn: CGFloat]
    let trashing: [Problem]
    let marked: Set<String>
    let isStriped: Bool
    @Binding var marks: [String: Bool]

    var body: some View {
        let isMarked = row.path.map(marked.contains) ?? false
        let blocker = isMarked ? nil : blocker
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if row.problem.kind.trashesFromTable {
                    Toggle(isOn: Binding(get: { isMarked }, set: { toggle($0) })) { name(isMarked: isMarked) }
                        .toggleStyle(.checkbox)
                        .disabled(blocker != nil)
                } else {
                    name(isMarked: false)
                }
                if row.isNewest { NewestTag() }
                if !row.preferredFor.isEmpty { PreferredTag(names: row.preferredFor) }
            }
            .frame(width: widths[.name], alignment: .leading)
            ForEach(ConflictColumn.resizable, id: \.self) { column in
                Text(row.text(of: column))
                    .lineLimit(1)
                    .truncationMode(column == .folder ? .middle : .tail)
                    .help(row.text(of: column))
                    .padding(.leading, ConflictColumn.spacing)
                    .frame(width: widths[column]! + ConflictColumn.spacing + (column == .details && row.fixes.isEmpty ? widths[.actions] ?? 0 : 0), alignment: .leading)
            }
            if let actions = widths[.actions], actions > 0, !row.fixes.isEmpty {
                FixButtons(fixes: row.fixes, family: row.problem.family)
                    .controlSize(.small)
                    .frame(width: actions, alignment: .trailing)
            }
        }
        .frame(minHeight: 22)
        .foregroundStyle(isMarked ? .secondary : blocker != nil ? .tertiary : .primary)
        .padding(.horizontal, ConflictColumn.inset)
        .padding(.vertical, 2)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background { ListRowBackground(isSelected: false, isStriped: isStriped, joinsAbove: false, joinsBelow: false) }
        .help(blocker ?? "")
        .contextMenu {
            if row.canReveal, let path = row.path {
                Button("Show in Finder") { model.apply(.reveal([path]), family: row.problem.family) }
            }
        }
    }

    private func name(isMarked: Bool) -> some View {
        Text(row.name)
            .strikethrough(isMarked)
            .lineLimit(1)
            .truncationMode(.middle)
    }


    private var blocker: String? {
        guard row.problem.kind.trashesFromTable, let path = row.path, !row.problem.trashable.contains(path) else { return nil }
        if ActiveSource.isAdobeFonts(path) { return "Managed by Creative Cloud. Deactivate this font in Adobe Fonts or Creative Cloud." }
        if ActivationEngine.isProtected(path) { return "macOS or an app needs this file." }
        return "This file contains the only copy of a font."
    }

    private func toggle(_ isOn: Bool) {
        guard let path = row.path else { return }
        guard isOn else {
            marks[path] = false
            return
        }
        var set = marked
        set.insert(path)
        marks[path] = true
        for group in trashing.flatMap(\.copyGroups) where group.contains(path) && group.allSatisfy(set.contains) {
            if let other = group.first(where: { $0 != path }) {
                set.remove(other)
                marks[other] = false
            }
        }
    }
}

private struct TrashBar: View {
    @Environment(AppModel.self) private var model
    let problems: [Problem]
    let marked: Set<String>
    @Binding var marks: [String: Bool]

    var body: some View {
        let paths = marked.sorted()
        HStack(spacing: 12) {
            Text(paths.isEmpty ? "No files selected"
                : paths.count == 1 ? "1 file selected" : "\(paths.count.plain) files selected")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !paths.isEmpty {
                Button("Deselect All") {
                    marks = Dictionary(problems.flatMap(\.files).map { ($0.path, false) }, uniquingKeysWith: { first, _ in first })
                }
            } else if problems.contains(where: { !$0.extraCopies.isEmpty }) {
                Button("Select Extra Copies") { marks = [:] }
                    .help("Select extra copies to move to the Trash, keeping at least one copy of each font.")
            }
            Button(paths.isEmpty ? "Move to Trash" : paths.count == 1 ? "Move 1 File to Trash" : "Move \(paths.count.plain) Files to Trash") {
                model.trashExtraCopies(of: problems.filter { $0.files.contains { marked.contains($0.path) } }, paths: paths)
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

private struct NewestTag: View {
    var body: some View {
        Tag(text: "Newest", tint: .green).help("The highest version. Usually the copy to keep.")
    }
}

private struct PreferredTag: View {
    let names: [String]

    var body: some View {
        Tag(text: "Preferred", tint: .blue).help("Apps that ask for \(names.listed()) get this font.")
    }
}

private struct FixButtons: View {
    @Environment(AppModel.self) private var model
    let fixes: [ProblemFix]
    let family: String?

    static func width(of lines: [ConflictLine]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let widest = lines.map { line -> CGFloat in
            guard case .row(let row, _) = line.content, !row.fixes.isEmpty else { return 0 }
            return row.fixes.reduce(CGFloat(6 * (row.fixes.count - 1))) { $0 + (title($1) as NSString).size(withAttributes: [.font: font]).width + 20 }
        }.max() ?? 0
        return widest > 0 ? (widest + ConflictColumn.spacing).rounded(.up) : 0
    }

    private static func title(_ fix: ProblemFix) -> String {
        guard case .removeFromAdobeFonts(let paths) = fix else { return fix.title }
        return CreativeCloud.page(for: paths) != nil ? "Manage in Adobe Fonts" : "Manage in Creative Cloud"
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(fixes, id: \.self) { fix in
                Button(Self.title(fix)) { model.apply(fix, family: family) }
            }
        }
    }
}
