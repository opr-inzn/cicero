import CiceroCore
import Foundation

public enum StatusCommand {
    public static func library(in context: LibraryContext) -> JSON {
        let families = context.listedFamilies
        var answer = JSONObject.answer()
        answer.set("familyCount", families.count)
        answer.set("styleCount", families.reduce(0) { $0 + $1.faces.count })
        answer.set("activeFamilyCount", families.count(where: \.hasActive))
        answer.set("lastScan", context.lastScan)
        answer.set("hidden", context.hidden)
        answer.set("locations", ListCommand.locations(context))
        let problems = ProblemDetector.detect(in: context.library, data: context.data, locations: context.environment.locations)
        answer.set("problems", problems.map { problem -> JSON in
            var object = JSONObject()
            object.set("kind", problem.kind.rawValue)
            object.set("message", problem.summary.isEmpty ? problem.title : "\(problem.title): \(problem.summary)")
            object.set("paths", problem.files.map(\.path))
            return object.json
        })
        return answer.json
    }

    public static func family(_ name: String, style: String?, allStyles: Bool, in context: LibraryContext) throws -> JSON {
        if style != nil, allStyles { throw CommandError.invalid("Use --style or --all-styles, not both.") }
        let family = try Names.family(name, in: context)
        let chosen = try style.map { try Names.style($0, of: family).id }
        var answer = JSONObject.answer()
        for field in Describer(context).familyStatus(family, details: { allStyles || $0.id == chosen }).fields {
            answer[field.key] = field.value
        }
        return answer.json
    }
}

public enum CoverageCommand {
    public static func run(family name: String, set id: String?, text: String?, in context: LibraryContext) async throws -> JSON {
        guard (id == nil) != (text == nil) else { throw CommandError.invalid("Give --set <id> or --text \"…\", one of them.") }
        try FindCommand.needsCoverage(context)
        let family = try Names.family(name, in: context)
        let face = family.regular.face
        var answer = JSONObject.answer()
        answer.set("family", family.id)
        answer.set("style", face.styleName)
        let wanted: [UInt32]
        if let id {
            let set = try FindCommand.characterSet(id, in: context)
            answer.set("set", set.id)
            wanted = set.scalars
        } else {
            let scalars = CoverageSearch.scalars(in: text!)
            guard !scalars.isEmpty else { throw CommandError.invalid("--text has no characters to check.") }
            answer.set("text", text!)
            wanted = scalars
        }
        guard let coverage = await context.faceCoverage(computing: face) else {
            throw CommandError(.failed, "Cicero can’t read the characters of \(family.id).")
        }
        let missing = wanted.filter { !coverage.scalars.contains($0) }
        answer.set("covered", missing.isEmpty)
        answer.set("missingCount", missing.count)
        answer.set("missing", missing.map { value -> JSON in
            var character = JSONObject()
            character.set("character", Unicode.Scalar(value).map { String(Character($0)) } ?? "")
            character.set("unicode", String(format: "U+%04X", value))
            return character.json
        })
        return answer.json
    }
}

public enum ListCommand {
    public enum What: String, CaseIterable, Sendable {
        case families, tags, folders, locations, foundries, coverage
    }

    public static func run(_ what: What, options: FindOptions = FindOptions(), in context: LibraryContext) throws -> JSON {
        var answer = JSONObject.answer()
        let families = context.listedFamilies
        switch what {
        case .families:
            return try FindCommand.run(options, in: context)
        case .tags:
            let counts = Dictionary(grouping: families.flatMap { context.data.tags(of: $0.id) }, by: { $0 }).mapValues(\.count)
            answer.set("tags", context.data.tags.map { tag -> JSON in
                var object = JSONObject()
                object.set("name", tag)
                object.set("color", context.data.tagColors[tag]?.rawValue)
                object.set("familyCount", counts[tag] ?? 0)
                return object.json
            })
        case .folders:
            let listed = Set(families.map(\.id))
            answer.set("folders", context.data.sets.map { set -> JSON in
                var object = JSONObject()
                object.set("id", set.id.uuidString)
                object.set("name", set.name)
                object.set("familyCount", set.memberFamilies.count { listed.contains($0) })
                return object.json
            })
        case .locations:
            answer.set("locations", locations(context))
        case .foundries:
            let counts = Dictionary(grouping: families.compactMap(context.foundryName), by: { $0 }).mapValues(\.count)
            answer.set("foundries", counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name -> JSON in
                var object = JSONObject()
                object.set("name", name)
                object.set("familyCount", counts[name]!)
                return object.json
            })
        case .coverage:
            try FindCommand.needsCoverage(context)
            answer.set("coverage", context.allSets.map { set -> JSON in
                var object = JSONObject()
                object.set("id", set.id)
                object.set("name", set.name)
                object.set("group", group(of: set))
                object.set("characterCount", set.scalars.count)
                return object.json
            })
        }
        return answer.json
    }

    static func locations(_ context: LibraryContext) -> [JSON] {
        context.data.namedFolders.map { folder -> JSON in
            var object = JSONObject()
            object.set("id", folder.id.uuidString)
            object.set("name", folder.displayName)
            object.set("path", folder.path)
            return object.json
        }
    }

    static func group(of set: CharacterSetDefinition) -> String {
        switch set.groupID {
        case CharacterSetCatalog.latinSeriesID: "latin"
        case CharacterSetCatalog.adobeSeriesID: "adobeLatin"
        default: set.groupID
        }
    }
}
