import CiceroCore
import Foundation

/// A change the `cicero` command makes: what it sends Cicero while Cicero is open (see `Requests`), and what it does
/// itself while Cicero is closed. Names are as typed; whoever makes the change looks them up in its own library, which
/// in Cicero is the one its window shows. The format is private: only Cicero and its own command read it.
public enum WriteCommand: Codable, Sendable, Equatable {
    case activate(families: [String], folder: String?, tag: String?, untilQuit: Bool)
    case deactivate(families: [String], folder: String?, tag: String?)
    case tagCreate(name: String, color: String?)
    case tagAdd(tag: String, families: [String])
    case tagRemove(tag: String, families: [String])
    case folderCreate(name: String)
    case folderAdd(folder: String, families: [String])
    case folderRemove(folder: String, families: [String])

    /// Whether it turns fonts on or off, which a scan after it shows.
    public var activates: Bool {
        switch self {
        case .activate, .deactivate: true
        default: false
        }
    }

    /// Whether it names families or their fonts, which needs the library.
    public var needsLibrary: Bool {
        switch self {
        case .tagCreate, .folderCreate: false
        default: true
        }
    }
}

/// A change and how to make it.
public struct WriteRequest: Codable, Sendable, Equatable {
    public var command: WriteCommand
    /// The user said yes to the question the change asks (`--yes`, or y in the terminal).
    public var confirmed: Bool
    /// Fonts Cicero's settings hide that the names may name, or the other way round.
    public var shown: ShownFonts

    public init(_ command: WriteCommand, confirmed: Bool = false, shown: ShownFonts = ShownFonts()) {
        self.command = command
        self.confirmed = confirmed
        self.shown = shown
    }
}

/// What makes the changes: Cicero itself while it's open (its model, with the same functions as a click, toasts and
/// Undo), or the command while Cicero is closed (`ClosedAppWriter`). Turning fonts on and off saves the activation
/// records too.
@MainActor
public protocol Writer: AnyObject {
    /// The user's data as it is now, with Cicero's settings.
    var data: UserData { get }
    /// Changes the data and saves it.
    func update(_ change: (inout UserData) -> Void)
    /// Turns the styles on, until Cicero quits with `untilQuit`; `title` names them in a toast.
    func activate(_ faces: [LibraryFace], untilQuit: Bool, title: String) async -> ActivationResult
    func deactivate(_ faces: [LibraryFace]) async -> ActivationResult
    /// Whether this is Cicero, which can turn fonts on until it quits.
    var isApp: Bool { get }
}

/// Makes a change and answers what it did: `{ "schema": 1, "changed": [...], "unchanged": [...], "failed": [ { "family",
/// "path", "reason" } ] }`. Names are never guessed: one that isn't exact (ignoring case) stops it with near names, and
/// nothing changes. A change that asks first stops with `needsConfirmation` and the question, unless confirmed.
@MainActor
public enum WriteRunner {
    public static func run(_ request: WriteRequest, in context: LibraryContext, writer: Writer) async throws -> JSON {
        switch request.command {
        case .activate(let families, let folder, let tag, let untilQuit):
            if untilQuit, !writer.isApp {
                throw CommandError(.appNotOpen, "--until-quit needs Cicero open: Cicero turns those fonts off when it quits. Open Cicero, or leave out --until-quit.")
            }
            let (faces, title) = try targets(families: families, folder: folder, tag: tag, in: context)
            let wanted = faces.filter(untilQuit ? \.canActivateTemporarily : \.canActivate)
            if !request.confirmed, let prompt = ActivationQuestions.many(for: wanted, title: title, temporarily: untilQuit, data: writer.data) {
                throw CommandError(.needsConfirmation, "Turning on \(prompt.families.formatted()) families asks first. Add --yes to turn them on.",
                                   question: .init(kind: "manyFamilies", title: "Activate \(prompt.families.formatted()) Families?",
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
            // The colour the app's New Tag starts with: the first one no tag has.
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
        case .folderCreate(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CommandError.invalid("A folder needs a name.") }
            // A second folder of the same name would make the name fit two folders: the command takes the one there.
            if let existing = writer.data.sets.first(where: { Names.fold($0.name) == Names.fold(trimmed) }) {
                return changes(changed: [], unchanged: [existing.name])
            }
            writer.update { $0.addSet(named: trimmed) }
            return changes(changed: [trimmed], unchanged: [])
        case .folderAdd(let typed, let families), .folderRemove(let typed, let families):
            let adding = if case .folderAdd = request.command { true } else { false }
            let set = try Names.folder(typed, in: writer.data)
            let ids = try familyIDs(families, in: context)
            // In: the family whole. A folder with only some of its styles gets the rest; taking it out takes those too.
            let changed = ids.filter { adding ? !set.families.contains($0) : (set.families.contains($0) || set.styles[$0] != nil) }
            if !changed.isEmpty { writer.update { $0.setMembership(adding, for: changed, in: set.id) } }
            return changes(changed: changed, unchanged: ids.filter { !changed.contains($0) })
        }
    }

    /// The families by their names, each once, in the order given; at least one.
    static func familyIDs(_ names: [String], in context: LibraryContext) throws -> [String] {
        guard !names.isEmpty else { throw CommandError.invalid("Give at least one family.") }
        var seen = Set<String>()
        return try names.map { try Names.family($0, in: context).id }.filter { seen.insert($0).inserted }
    }

    /// The styles to turn on or off: every style of the families; a folder's, which can be only some of a family's; or
    /// every style of the families with the tag. And what a toast calls them.
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
        return (found.flatMap(\.faces), found.count == 1 ? found[0].name : "\(found.count.formatted()) families")
    }

    /// Each family once: changed when a style of it turned, failed for each file that didn't, unchanged when there was
    /// nothing to turn.
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
