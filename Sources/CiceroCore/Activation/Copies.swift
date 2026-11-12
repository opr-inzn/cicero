import Foundation

public struct FaceCopy: Hashable, Sendable {
    public let face: FontFace
    public let state: FaceState
    public let app: String?

    public init(face: FontFace, state: FaceState, app: String? = nil) {
        self.face = face
        self.state = state
        self.app = app
    }

    init(_ face: LibraryFace) {
        self.init(face: face.face, state: face.state, app: face.app)
    }

    public var libraryFace: LibraryFace { LibraryFace(face: face, state: state, app: app) }

    func libraryFace(among all: [FaceCopy]) -> LibraryFace {
        LibraryFace(face: face, state: state, copies: all.filter { $0.face.path != face.path }, app: app)
    }
}

public struct CopySource: Identifiable, Hashable, Sendable {
    public struct Choice: Hashable, Sendable {
        public let style: LibraryFace
        public let copy: FaceCopy
        public let isInUse: Bool
    }

    public let id: String
    public let location: [String]
    public let name: String
    public let choices: [Choice]
    public var isInUse: Bool { choices.allSatisfy(\.isInUse) }
    public var version: String? {
        choices.compactMap(\.copy.face.version).max { FontVersion.precedes($0, $1) }.map(FontFace.displayVersion)
    }
}

public struct CopySwitch: Sendable {
    public var target: LibraryFace?
    public var others: [LibraryFace]
}

public struct CopySwitchPlan: Sendable {
    public var switches: [CopySwitch]
    public var styles: [LibraryFace]
    public var alsoTurnsOff: [String]
    public var leavesOtherCopiesOn: Bool

    public var isEmpty: Bool { switches.allSatisfy { $0.target == nil && $0.others.isEmpty } }
}

public enum CopyChooser {
    public static func sources(of styles: [LibraryFace], folders: [WatchedFolder], records: ActivationRecords, locations: Locations) -> [CopySource] {
        struct Candidate {
            var style: LibraryFace
            var copy: FaceCopy
            var folder: String
            var isInUse: Bool
            var place = Place(key: "", location: [])
        }
        var candidates: [Candidate] = []
        for style in styles {
            let all = [FaceCopy(style)] + style.copies
            let installedFrom = Set(all.compactMap { $0.state.isActive ? records.installedCopies[$0.face.path] : nil })
            for copy in all {
                let path = copy.face.path
                let origin = records.installedCopies[path]
                guard isChoosable(copy, installedFrom: origin, locations: locations) else { continue }
                let folder = ((origin ?? path) as NSString).deletingLastPathComponent
                candidates.append(Candidate(style: style, copy: copy, folder: folder, isInUse: copy.state.isActive || installedFrom.contains(path)))
            }
        }
        let placed = places(of: candidates.map { ($0.style.id, $0.folder) }, folders: folders, locations: locations)
        for index in candidates.indices { candidates[index].place = placed[index] }
        func key(_ candidate: Candidate) -> String { candidate.place.key }

        let byStyle = Dictionary(grouping: candidates, by: \.style.id)
        let keys = Set(byStyle.values.filter { Set($0.map(key)).count > 1 }.flatMap { $0.map(key) })
        guard !keys.isEmpty else { return [] }
        let found = Dictionary(grouping: candidates.filter { keys.contains(key($0)) }, by: key)
        var sources = found.map { key, members in
            let choices = styles.compactMap { style -> CopySource.Choice? in
                guard let best = members.filter({ $0.style.id == style.id }).min(by: { better($0, than: $1) }) else { return nil }
                return CopySource.Choice(style: style, copy: best.copy, isInUse: best.isInUse)
            }
            let location = members[0].place.location
            return CopySource(id: key, location: location, name: location.last ?? "", choices: choices)
        }
        for (_, same) in Dictionary(grouping: sources.indices, by: { sources[$0].name }) where same.count > 1 {
            let paths = same.map { sources[$0].id.split(separator: "/").map(String.init).dropLast() }
            var above = paths.map { _ in "" }
            for level in 1...Swift.max(1, paths.map(\.count).max() ?? 1) {
                let names = paths.map { $0.count >= level ? $0[$0.count - level] : "" }
                if Set(names).count == names.count {
                    above = names
                    break
                }
            }
            for (index, name) in zip(same, above) where !name.isEmpty {
                let source = sources[index]
                sources[index] = CopySource(id: source.id, location: source.location, name: "\(source.name) (\(name))", choices: source.choices)
            }
        }
        return sources.sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }

        func better(_ a: Candidate, than b: Candidate) -> Bool {
            if a.copy.state.isActive != b.copy.state.isActive { return a.copy.state.isActive }
            if a.isInUse != b.isInUse { return a.isInUse }
            let (va, vb) = (a.copy.face.version ?? "", b.copy.face.version ?? "")
            if va != vb { return FontVersion.precedes(vb, va) }
            return a.copy.face.id < b.copy.face.id
        }
    }

    public static func plan(_ source: CopySource, records: ActivationRecords, library: Library) -> CopySwitchPlan {
        var switches: [CopySwitch] = []
        var leavesOtherCopiesOn = false
        var leaving = Set<String>()
        for choice in source.choices {
            let all = [FaceCopy(choice.style)] + choice.style.copies
            let chosen = choice.copy.face.path
            let staying = Set([chosen] + all.filter { $0.state.isActive && records.installedCopies[$0.face.path] == chosen }.map(\.face.path))
            var others: [LibraryFace] = []
            for copy in all where copy.state.isActive && !staying.contains(copy.face.path) {
                if isManaged(copy, records: records) {
                    others.append(copy.libraryFace(among: all))
                    leaving.insert(copy.face.path)
                } else {
                    leavesOtherCopiesOn = true
                }
            }
            let target = choice.isInUse ? nil : choice.copy.libraryFace
            switches.append(CopySwitch(target: target, others: others))
        }
        let moving = Set(source.choices.map(\.style.id))
        var alsoTurnsOff: [String] = []
        for family in library.families {
            for face in family.faces where face.state.isActive && !moving.contains(face.id) && leaving.contains(face.face.path) {
                alsoTurnsOff.append("\(family.name) \(face.face.styleName)")
            }
        }
        return CopySwitchPlan(switches: switches, styles: source.choices.map(\.style), alsoTurnsOff: alsoTurnsOff,
                              leavesOtherCopiesOn: leavesOtherCopiesOn)
    }

    static func isChoosable(_ copy: FaceCopy, installedFrom origin: String?, locations: Locations) -> Bool {
        let path = copy.face.path
        guard copy.app == nil, !ActivationEngine.isProtected(path) else { return false }
        switch copy.state {
        case .active(.fontsFolder): return origin != nil
        case .active(.inPlace), .active(.temporary): return true
        case .inactive:
            if path.hasPrefix(locations.userFonts.path + "/") { return origin != nil }
            return !path.hasPrefix(locations.allUsersFonts.path + "/")
        default: return false
        }
    }

    static func isManaged(_ copy: FaceCopy, records: ActivationRecords) -> Bool {
        guard copy.app == nil else { return false }
        switch copy.state.source {
        case .inPlace, .temporary(.untilQuit): return true
        case .fontsFolder: return records.installedCopies[copy.face.path] != nil
        default: return false
        }
    }

    public struct Place: Hashable, Sendable {
        public let key: String
        public let location: [String]
    }

    public static func places(of copies: [(style: FaceID, folder: String)], folders: [WatchedFolder], locations: Locations) -> [Place] {
        let located = copies.map { location(of: $0.folder, folders: folders, locations: locations) }
        var below = Array(repeating: [String](), count: copies.count)
        for (_, indices) in Dictionary(grouping: copies.indices, by: { located[$0].root }) {
            let parting = Dictionary(grouping: indices, by: { copies[$0].style }).values
                .filter { Set($0.map { located[$0].below }).count > 1 }
                .flatMap { $0.map { located[$0].below } }
            guard let first = parting.first else { continue }
            let common = parting.dropFirst().reduce(first) { common, below in Array(zip(common, below).prefix { $0 == $1 }.map(\.0)) }
            for index in indices { below[index] = Array(located[index].below.prefix(common.count + 1)) }
        }
        return copies.indices.map { index in
            Place(key: ([located[index].root] + below[index]).joined(separator: "/"), location: [located[index].name] + below[index])
        }
    }

    struct Location {
        var root: String
        var name: String
        var below: [String]
    }

    static func location(of folder: String, folders: [WatchedFolder], locations: Locations) -> Location {
        if locations.isInInactiveFolder(folder + "/") { return Location(root: locations.inactiveFolder.path, name: "Inactive", below: []) }
        let root = folders.filter { folder == $0.path || folder.hasPrefix($0.path + "/") }.min { $0.path.count < $1.path.count }
        guard let root else { return Location(root: folder, name: (folder as NSString).lastPathComponent, below: []) }
        return Location(root: root.path, name: root.displayName, below: folder.dropFirst(root.path.count).split(separator: "/").map(String.init))
    }
}

enum FontVersion {
    static func number(_ version: String) -> [Double] {
        let parts = version.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }.split(separator: ".")
        guard let major = parts.first else { return [] }
        return [Double(parts.count > 1 ? "\(major).\(parts[1])" : String(major)) ?? 0] + parts.dropFirst(2).compactMap { Double($0) }
    }

    static func precedes(_ a: String, _ b: String) -> Bool {
        number(a).lexicographicallyPrecedes(number(b))
    }
}

extension FontFace {
    func at(_ path: String) -> FontFace {
        FontFace(
            id: FaceID(path: path, index: id.index), postScriptName: postScriptName, familyName: familyName, styleName: styleName,
            fullName: fullName, weight: weight, isItalic: isItalic, isMonospaced: isMonospaced, familyClass: familyClass,
            panose: panose, letterShape: letterShape, manufacturer: manufacturer, version: version, designer: designer, vendorID: vendorID, weightAxis: weightAxis,
            width: width, axes: axes, isAtOrigin: isAtOrigin, year: year, embedding: embedding, features: features, figures: figures,
            localizedFamilyNames: localizedFamilyNames
        )
    }
}

extension Family {
    public var adobeFontsOnly: Family? {
        if isAdobeFonts { return self }
        let faces = faces.compactMap(\.adobeFontsCopy)
        guard !faces.isEmpty else { return nil }
        return Family(name: id, faces: faces, state: LibraryScanner.familyState(of: faces), folderIDs: folderIDs, manufacturer: manufacturer)
    }

    public func only(inLocation id: UUID) -> Family? {
        if id == WatchedFolder.adobeFontsID { return adobeFontsOnly }
        let faces = faces.filter { $0.folderIDs.contains(id) }
        guard !faces.isEmpty else { return nil }
        guard faces.count < self.faces.count else { return self }
        return Family(name: self.id, faces: faces, state: LibraryScanner.familyState(of: faces), folderIDs: folderIDs, manufacturer: manufacturer)
    }
}

private extension LibraryFace {
    var adobeFontsCopy: LibraryFace? {
        if isAdobeFonts { return self }
        guard let adobe = copies.first(where: { ActiveSource.isAdobeFonts($0.face.path) }) else { return nil }
        let others = [FaceCopy(self)] + copies.filter { $0.face.path != adobe.face.path }
        return LibraryFace(face: adobe.face, state: adobe.state, copies: others, dateAdded: dateAdded, app: adobe.app, folderIDs: folderIDs)
    }
}
