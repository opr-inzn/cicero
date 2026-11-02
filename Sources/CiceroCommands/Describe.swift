import CiceroCore
import Foundation

/// Families and styles in the JSON of the contract (CLI-PLAN.md, section 0b). A family-level text field whose styles
/// differ says "mixed"; a field without a value is left out; lists are written also when they're empty.
public struct Describer {
    let context: LibraryContext
    /// Family → the folders (`sets`) it's in, families it has only some styles of too.
    private let folders: [String: [FontSet]]
    /// Bundle ID → an app's name, from the application sets.
    private let appNames: [String: String]

    public static let mixed = "mixed"

    public init(_ context: LibraryContext) {
        self.context = context
        var folders: [String: [FontSet]] = [:]
        var appNames: [String: String] = [:]
        for set in context.data.sets {
            for family in set.memberFamilies { folders[family, default: []].append(set) }
            for app in set.apps where appNames[app.bundleID] == nil { appNames[app.bundleID] = app.name }
        }
        self.folders = folders
        self.appNames = appNames
    }

    /// One value for every style, "mixed" when they differ; nil when none has one.
    static func shared(_ values: [String?]) -> String? {
        var found: String?
        for value in values.compactMap({ $0 }) {
            if found == nil { found = value } else if found != value { return mixed }
        }
        return found
    }

    // MARK: Families

    /// A family as `find` and `list families` give it.
    public func family(_ family: Family) -> JSONObject {
        var object = JSONObject()
        let faces = family.faces.map(\.face)
        object.set("id", family.id)
        object.set("name", family.name)
        object.set("foundry", context.foundryName(family))
        object.set("manufacturer", Self.shared(faces.map(\.manufacturer)))
        object.set("class", context.classificationName(family))
        let status: String
        var app: String?
        switch family.state {
        case .active: status = "active"
        case .partial: status = "partial"
        case .inactive: status = "inactive"
        case .appOnly(let name):
            status = "appOnly"
            app = FaceState.appDescription(name)
        case .system: status = "system"
        }
        object.set("status", status)
        object.set("app", app)
        object.set("styleCount", family.faces.count)
        object.set("tags", context.data.tags(of: family.id))
        object.set("folders", (folders[family.id] ?? []).map { set -> JSON in
            var folder = JSONObject()
            folder.set("id", set.id.uuidString)
            folder.set("name", set.name)
            return folder.json
        })
        object.set("rating", context.data.familyRatings[family.id].flatMap { (1...5).contains($0) ? $0 : nil })
        object.set("added", family.dateAdded)
        object.set("released", family.year)
        object.set("version", Self.shared(faces.map { $0.version.map(FontFace.displayVersion) }))
        object.set("designer", Self.shared(faces.map(\.designer)))
        object.set("vendorID", Self.shared(faces.map(\.vendorID)))
        object.set("fsType", Self.shared(faces.map { $0.embedding?.rawValue }))
        object.set("coverage", coverage(of: family.regular.face, sets: false))
        return object
    }

    /// A family as `status <family>` gives it: the fields of `family(_:)`, its note, what its files' name tables say,
    /// the sets its regular style covers completely, and its styles, each with its details when `details` asks.
    public func familyStatus(_ family: Family, details: (LibraryFace) -> Bool) -> JSONObject {
        var object = self.family(family)
        let faces = family.faces.map(\.face)
        let names = FileNames.read(faces)
        // In the contract's order: after the family's own fields, before coverage.
        let coverage = object["coverage"]
        object["coverage"] = nil
        object.set("note", context.data.familyNotes[family.id])
        object.set("description", Self.shared(faces.map { names[$0.id]?.description }))
        object.set("copyright", Self.shared(faces.map { names[$0.id]?.copyright }))
        object.set("designerURL", Self.shared(faces.map { names[$0.id]?.designerURL }))
        object.set("manufacturerURL", Self.shared(faces.map { names[$0.id]?.manufacturerURL }))
        object.set("license", Self.shared(faces.map { names[$0.id]?.license }))
        object.set("licenseURL", Self.shared(faces.map { names[$0.id]?.licenseURL }))
        if coverage != nil { object.set("coverage", self.coverage(of: family.regular.face, sets: true)) }
        object.set("styles", family.faces.map { face in
            style(face, details: details(face) ? names[face.id] ?? FileNames() : nil).json
        })
        return object
    }

    // MARK: Styles

    /// A style, short; with `details` (what its file's name table says), its details too.
    public func style(_ libraryFace: LibraryFace, details: FileNames?) -> JSONObject {
        let face = libraryFace.face
        var object = JSONObject()
        object.set("name", face.styleName)
        object.set("postScriptName", face.postScriptName)
        object.set("weight", min(max(Int(face.styleWeight.rounded()), 1), 1000))
        object.set("italic", face.isItalic)
        object.set("width", min(max(face.width, 1), 9))
        switch libraryFace.state {
        case .active(let source):
            object.set("status", "active")
            object.set("activeFrom", activeFrom(source, path: face.path))
            if source == .temporary(.whileAppsRun) {
                let bundleIDs = context.data.records.temporary[face.path]?.apps ?? []
                object.set("apps", bundleIDs.map { appNames[$0] ?? $0 })
            }
        case .inactive:
            object.set("status", "inactive")
        case .appOnly(let app):
            object.set("status", "appOnly")
            object.set("app", FaceState.appDescription(app))
        }
        object.set("path", face.path)
        object.set("indexInFile", face.id.index)
        object.set("otherCopies", libraryFace.otherCopies)
        object.set("axes", axes(of: face))
        guard let details else { return object }
        object.set("version", face.version.map(FontFace.displayVersion))
        object.set("released", face.year)
        object.set("designer", face.designer)
        object.set("designerURL", details.designerURL)
        object.set("manufacturer", face.manufacturer)
        object.set("manufacturerURL", details.manufacturerURL)
        object.set("vendorID", face.vendorID)
        object.set("description", details.description)
        object.set("copyright", details.copyright)
        object.set("license", details.license)
        object.set("licenseURL", details.licenseURL)
        object.set("fsType", face.embedding?.rawValue)
        object.set("coverage", coverage(of: face, sets: true))
        return object
    }

    /// Where an active style is on from: `cicero` for Cicero's Library while fonts are installed into it, `inLocation`
    /// for other files Cicero turned on where they are.
    func activeFrom(_ source: ActiveSource, path: String) -> String {
        switch source {
        case .macOS: return "macOS"
        case .allUsers: return "allUsers"
        case .app, .otherApp: return "other"
        case .adobeFonts: return "adobeFonts"
        case .fontsFolder: return "fontsFolder"
        case .inPlace:
            let data = context.data
            if data.installsIntoFontLibrary, !data.fontLibraryPath.isEmpty {
                let library = URL(fileURLWithPath: data.fontLibraryPath).standardizedFileURL.path + "/"
                if URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(library) { return "cicero" }
            }
            return "inLocation"
        case .temporary(.untilQuit): return "untilQuit"
        case .temporary(.whileAppsRun): return "whileAppOpen"
        }
    }

    /// A variable style's axes, as its file says how far each goes, without those the font hides; none for a static style.
    func axes(of face: FontFace) -> [JSON] {
        guard !face.axes.isEmpty else { return [] }
        return FontLoader.shared.axes(of: face).filter { !$0.isHidden }.map { range in
            var axis = JSONObject()
            axis.set("tag", range.tag)
            axis.set("name", range.name)
            axis.set("value", face.axes.first { $0.tag == range.tag }?.value ?? range.defaultValue)
            axis.set("minimum", range.minimum)
            axis.set("maximum", range.maximum)
            axis.set("default", range.defaultValue)
            return axis.json
        }
    }

    // MARK: Coverage

    /// The series whose largest step `coverage.largest` gives, by their keys in the JSON.
    static let largestSeries: [(key: String, id: String)] = [("latin", CharacterSetCatalog.latinSeriesID), ("adobeLatin", CharacterSetCatalog.adobeSeriesID)]

    /// What a face covers: how many characters, the largest step of each series it covers completely (a list with one
    /// id, or none), and with `sets` every set it covers completely. nil while it isn't checked yet.
    func coverage(of face: FontFace, sets: Bool) -> JSONObject? {
        guard let coverage = context.faceCoverage(face) else { return nil }
        var object = JSONObject()
        object.set("characterCount", coverage.scalars.count)
        var largest = JSONObject()
        for series in Self.largestSeries {
            largest.set(series.key, [context.largest(in: series.id, for: face)?.id].compactMap { $0 })
        }
        object.set("largest", largest)
        if sets {
            object.set("sets", context.allSets.filter { context.missingCount($0, face) == 0 }.map(\.id))
        }
        return object
    }
}
