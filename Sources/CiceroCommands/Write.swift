import CiceroCore
import Foundation

public enum WriteCommand: Codable, Sendable, Equatable {
    case activate(families: [String], folder: String?, tag: String?, untilQuit: Bool)
    case deactivate(families: [String], folder: String?, tag: String?)
    case tagCreate(name: String, color: String?)
    case tagAdd(tag: String, families: [String])
    case tagRemove(tag: String, families: [String])
    case tagRename(tag: String, name: String)
    case tagDelete(tags: [String])
    case folderCreate(name: String)
    case folderAdd(folder: String, families: [String])
    case folderRemove(folder: String, families: [String])
    case folderRename(folder: String, name: String)
    case folderDelete(folders: [String])
    case rate(families: [String], stars: Int)
    case note(family: String, text: String, append: Bool)
    case rescan

    public var activates: Bool {
        switch self {
        case .activate, .deactivate: true
        default: false
        }
    }

    public var needsLibrary: Bool {
        switch self {
        case .tagCreate, .tagRename, .tagDelete, .folderCreate, .folderRename, .folderDelete, .rescan: false
        default: true
        }
    }
}

public struct WriteRequest: Codable, Sendable, Equatable {
    public var command: WriteCommand
    public var confirmed: Bool
    public var shown: ShownFonts

    public init(_ command: WriteCommand, confirmed: Bool = false, shown: ShownFonts = ShownFonts()) {
        self.command = command
        self.confirmed = confirmed
        self.shown = shown
    }
}

@MainActor
public protocol Writer: AnyObject {
    var data: UserData { get }
    func update(_ change: (inout UserData) -> Void)
    func activate(_ faces: [LibraryFace], untilQuit: Bool, title: String) async -> ActivationResult
    func deactivate(_ faces: [LibraryFace]) async -> ActivationResult
    func rescan() async
    var isApp: Bool { get }
    func renameTag(_ old: String, to new: String)
    func deleteTags(_ names: Set<String>)
    func renameFolder(_ id: UUID, to name: String)
    func deleteFolders(_ ids: Set<UUID>)
}

public extension Writer {
    func renameTag(_ old: String, to new: String) { update { $0.renameTag(old, to: new) } }
    func deleteTags(_ names: Set<String>) { update { $0.deleteTags(names) } }
    func renameFolder(_ id: UUID, to name: String) { update { $0.renameSet(id, to: name) } }
    func deleteFolders(_ ids: Set<UUID>) { update { $0.deleteSets(ids) } }
}

@MainActor
public enum WriteRunner {
    public static func run(_ request: WriteRequest, in context: LibraryContext, writer: Writer) async throws -> JSON {
        switch request.command {
        case .rescan:
            await writer.rescan()
            return changes(changed: [], unchanged: [])
        case .activate(let families, let folder, let tag, let untilQuit):
            if untilQuit, !writer.isApp {
                throw CommandError(.appNotOpen, "--until-quit needs Cicero open: Cicero turns those fonts off when it quits. Open Cicero, or leave out --until-quit.")
            }
            let (faces, title) = try targets(families: families, folder: folder, tag: tag, in: context)
            let wanted = faces.filter(untilQuit ? \.canActivateTemporarily : \.canActivate)
            if !request.confirmed, let prompt = ActivationQuestions.many(for: wanted, title: title, temporarily: untilQuit, data: writer.data) {
                throw CommandError(.needsConfirmation, "Turning on \(prompt.families.plain) families asks first. Add --yes to turn them on.",
                                   question: .init(kind: "manyFamilies", title: "Activate \(prompt.families.plain) Families?",
                                                   message: "Apps load every font that’s on as they open, so this many at once can slow them down."))
            }
            let result = wanted.isEmpty ? nil : await writer.activate(wanted, untilQuit: untilQuit, title: title)
            return answer(faces: faces, wanted: wanted, result: result, on: true)
        case .deactivate(let families, let folder, let tag):
            let (faces, _) = try targets(families: families, folder: folder, tag: tag, in: context)
            let wanted = faces.filter(\.canDeactivate)
            if !request.confirmed, let prompt = ActivationQuestions.movingOut(for: wanted, data: writer.data) {
                throw CommandError(.needsConfirmation, "\(prompt.message) Add --yes to turn them off anyway.",
                                   question: .init(kind: "movingOutOfSharedFolder", title: prompt.title, message: prompt.message))
            }
            let result = wanted.isEmpty ? nil : await writer.deactivate(wanted)
            return answer(faces: faces, wanted: wanted, result: result, on: false)
        case .tagCreate(let name, let color):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CommandError.invalid("A tag needs a name.") }
            var tagColor: TagColor?
            if let color {
                guard let known = TagColor(rawValue: color.lowercased()) else {
                    throw CommandError.invalid("“\(color)” isn’t a tag colour. Use one of: \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")).")
                }
                tagColor = known
            }
            if let existing = writer.data.tags.first(where: { Names.fold($0) == Names.fold(trimmed) }) {
                return changes(changed: [], unchanged: [existing])
            }
            let made = tagColor ?? TagColor.next(after: writer.data.tagColors.values)
            writer.update { $0.addTag(named: trimmed, color: made) }
            return changes(changed: [trimmed], unchanged: [])
        case .tagAdd(let typed, let families), .tagRemove(let typed, let families):
            let adding = if case .tagAdd = request.command { true } else { false }
            let tag = try Names.tag(typed, in: writer.data)
            let ids = try familyIDs(families, in: context)
            let has = Set(writer.data.families(tagged: tag))
            let changed = ids.filter { has.contains($0) != adding }
            if !changed.isEmpty { writer.update { $0.setTag(tag, adding, for: changed) } }
            return changes(changed: changed, unchanged: ids.filter { has.contains($0) == adding })
        case .tagRename(let typed, let name):
            let tag = try Names.tag(typed, in: writer.data)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CommandError.invalid("A tag needs a name.") }
            if trimmed == tag { return changes(changed: [], unchanged: [tag]) }
            if let other = writer.data.tags.first(where: { $0 != tag && Names.fold($0) == Names.fold(trimmed) }) {
                throw CommandError.invalid("There’s already a tag called “\(other)”. Nothing changed.")
            }
            writer.renameTag(tag, to: trimmed)
            return changes(changed: [trimmed], unchanged: [])
        case .tagDelete(let typed):
            guard !typed.isEmpty else { throw CommandError.invalid("Give at least one tag.") }
            var seen = Set<String>()
            let tags = try typed.map { try Names.tag($0, in: writer.data) }.filter { seen.insert($0).inserted }
            writer.deleteTags(Set(tags))
            return changes(changed: tags, unchanged: [])
        case .folderCreate(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CommandError.invalid("A folder needs a name.") }
            if let existing = writer.data.sets.first(where: { Names.fold($0.name) == Names.fold(trimmed) }) {
                return changes(changed: [], unchanged: [existing.name])
            }
            writer.update { $0.addSet(named: trimmed) }
            return changes(changed: [trimmed], unchanged: [])
        case .folderRename(let typed, let name):
            let set = try Names.folder(typed, in: writer.data)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CommandError.invalid("A folder needs a name.") }
            if trimmed == set.name { return changes(changed: [], unchanged: [set.name]) }
            if let other = writer.data.sets.first(where: { $0.id != set.id && Names.fold($0.name) == Names.fold(trimmed) }) {
                throw CommandError.invalid("There’s already a folder called “\(other.name)”. Nothing changed.")
            }
            writer.renameFolder(set.id, to: trimmed)
            return changes(changed: [trimmed], unchanged: [])
        case .folderDelete(let typed):
            guard !typed.isEmpty else { throw CommandError.invalid("Give at least one folder.") }
            var seen = Set<UUID>()
            let sets = try typed.map { try Names.folder($0, in: writer.data) }.filter { seen.insert($0.id).inserted }
            writer.deleteFolders(Set(sets.map(\.id)))
            return changes(changed: sets.map(\.name), unchanged: [])
        case .folderAdd(let typed, let families), .folderRemove(let typed, let families):
            let adding = if case .folderAdd = request.command { true } else { false }
            let set = try Names.folder(typed, in: writer.data)
            let ids = try familyIDs(families, in: context)
            let changed = ids.filter { adding ? !set.families.contains($0) : (set.families.contains($0) || set.styles[$0] != nil) }
            if !changed.isEmpty { writer.update { $0.setMembership(adding, for: changed, in: set.id) } }
            return changes(changed: changed, unchanged: ids.filter { !changed.contains($0) })
        case .rate(let families, let stars):
            guard (0...5).contains(stars) else { throw CommandError.invalid("Stars go from 1 to 5, or 0 to take the rating away.") }
            let ids = try familyIDs(families, in: context)
            let rating = stars == 0 ? nil : stars
            let changed = ids.filter { writer.data.familyRatings[$0] != rating }
            if !changed.isEmpty { writer.update { data in for id in changed { data.familyRatings[id] = rating } } }
            return changes(changed: changed, unchanged: ids.filter { !changed.contains($0) })
        case .note(let typed, let text, let append):
            let id = try Names.family(typed, in: context).id
            let old = writer.data.familyNotes[id]
            let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let note: String?
            if append {
                note = blank ? old : old.map { $0 + "\n" + text } ?? text
            } else {
                note = blank ? nil : text
            }
            guard note != old else { return changes(changed: [], unchanged: [id]) }
            writer.update { $0.familyNotes[id] = note }
            return changes(changed: [id], unchanged: [])
        }
    }

    static func familyIDs(_ names: [String], in context: LibraryContext) throws -> [String] {
        guard !names.isEmpty else { throw CommandError.invalid("Give at least one family.") }
        var seen = Set<String>()
        return try names.map { try Names.family($0, in: context).id }.filter { seen.insert($0).inserted }
    }

    static func targets(families: [String], folder: String?, tag: String?, in context: LibraryContext) throws -> (faces: [LibraryFace], title: String) {
        guard [!families.isEmpty, folder != nil, tag != nil].count(where: \.self) == 1 else {
            throw CommandError.invalid("Give families, --folder or --tag: one of them.")
        }
        if let folder {
            let set = try Names.folder(folder, in: context.data)
            let members = context.listedFamilies.filter { set.families.contains($0.id) || set.styles[$0.id] != nil }
            return (members.flatMap { family in family.faces.filter { set.contains(style: $0.face.postScriptName, of: family.id) } }, "“\(set.name)”")
        }
        if let tag {
            let name = try Names.tag(tag, in: context.data)
            let tagged = context.data.families(tagged: name)
            return (context.listedFamilies.filter { tagged.contains($0.id) }.flatMap(\.faces), "“\(name)”")
        }
        let ids = try familyIDs(families, in: context)
        let found = ids.compactMap { id in context.listedFamilies.first { $0.id == id } }
        return (found.flatMap(\.faces), found.count == 1 ? found[0].name : "\(found.count.plain) families")
    }

    static func answer(faces: [LibraryFace], wanted: [LibraryFace], result: ActivationResult?, on: Bool) -> JSON {
        let failedPaths = Set(result?.failed ?? [])
        var order: [String] = []
        var seen = Set<String>()
        for face in faces where seen.insert(face.face.familyName).inserted { order.append(face.face.familyName) }
        var changed: [String] = [], unchanged: [String] = []
        var failed: [JSON] = []
        for family in order {
            let turned = wanted.filter { $0.face.familyName == family }
            if turned.isEmpty {
                unchanged.append(family)
                continue
            }
            if turned.contains(where: { !failedPaths.contains($0.face.path) }) { changed.append(family) }
            var paths = Set<String>()
            for face in turned where failedPaths.contains(face.face.path) && paths.insert(face.face.path).inserted {
                var object = JSONObject()
                object.set("family", family)
                object.set("path", face.face.path)
                object.set("reason", on ? "macOS didn’t turn it on." : "It couldn’t be turned off.")
                failed.append(object.json)
            }
        }
        return changes(changed: changed, unchanged: unchanged, failed: failed)
    }

    static func changes(changed: [String], unchanged: [String], failed: [JSON] = []) -> JSON {
        var answer = JSONObject.answer()
        answer.set("changed", changed)
        answer.set("unchanged", unchanged)
        answer.set("failed", failed)
        return answer.json
    }
}
