import Foundation

/// Another file with the same face, as the library found it.
public struct FaceCopy: Hashable, Sendable {
    public let face: FontFace
    public let state: FaceState
    /// The app that loads it from its own folder, if one does.
    public let app: String?

    public init(face: FontFace, state: FaceState, app: String? = nil) {
        self.face = face
        self.state = state
        self.app = app
    }

    init(_ face: LibraryFace) {
        self.init(face: face.face, state: face.state, app: face.app)
    }

    /// The copy as a face of its own, to turn on or off.
    public var libraryFace: LibraryFace { LibraryFace(face: face, state: state, app: app) }

    /// The copy as a face of its own, with the style's other copies (`all` may have this one too), so that turning
    /// it off knows whether the file an installed copy came from is in the library.
    func libraryFace(among all: [FaceCopy]) -> LibraryFace {
        LibraryFace(face: face, state: state, copies: all.filter { $0.face.path != face.path }, app: app)
    }
}

/// A place a family's styles can be used from when they're in more than one, like each client's folder
/// when every client sent their own copy of a font.
public struct CopySource: Identifiable, Hashable, Sendable {
    /// The style in the library and the copy of it here.
    public struct Choice: Hashable, Sendable {
        public let style: LibraryFace
        public let copy: FaceCopy
        /// Whether the style is on from this copy, or from one Cicero installed from it.
        public let isInUse: Bool
    }

    /// The folder's path, or the watched folder's and the folders below it.
    public let id: String
    /// Where it is, from the watched folder it's in: ["Clients", "Acme"].
    public let location: [String]
    /// The folder's name, told apart from the other places': "Acme", "Globex".
    public let name: String
    /// The styles it has, in the order they were asked about.
    public let choices: [Choice]
    /// Every style it has is on from here.
    public var isInUse: Bool { choices.allSatisfy(\.isInUse) }
    /// The newest version among its copies, without the label: "1.002".
    public var version: String? {
        choices.compactMap(\.copy.face.version).max { FontVersion.precedes($0, $1) }.map(FontFace.displayVersion)
    }
}

/// One style moving to another copy of it: the copy to turn on (nil when it's on already) and the
/// copies Cicero turned on to turn off.
public struct CopySwitch: Sendable {
    public var target: LibraryFace?
    public var others: [LibraryFace]
}

/// What using a place's copies takes.
public struct CopySwitchPlan: Sendable {
    public var switches: [CopySwitch]
    /// The library's styles that move, for their switches to show where they're going.
    public var styles: [LibraryFace]
    /// Styles that go off too, as they're in a file that goes off with nothing else holding them: "Raanana Bold".
    public var alsoTurnsOff: [String]
    /// Another copy of a style stays on that Cicero doesn't turn off: macOS's, an app's, or one the user put in
    /// the Fonts folder. Apps may get that one.
    public var leavesOtherCopiesOn: Bool

    public var isEmpty: Bool { switches.allSatisfy { $0.target == nil && $0.others.isEmpty } }
}

/// Finds the places a font's styles can be used from, and what switching to one takes. Only copies Cicero
/// turns on and off count: those in the user's folders, Cicero's Deactivated folder or added one at a time,
/// and those it installed (which count as being where they were copied from). macOS's, apps', Adobe's and
/// files the user put in a Fonts folder are left alone.
public enum CopyChooser {
    /// The places the styles' copies are in, sorted by name; empty unless some style is in more than one.
    /// Each watched folder is a place, unless copies of one style are in different folders inside it: then it
    /// parts where their paths do (Clients/Acme and Clients/Globex are "Acme" and "Globex"). A place lists a
    /// style only when it has a copy of it.
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

        // Places that hold a style that's in more than one.
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
        // Places with the same name, like two watched folders called Fonts elsewhere, add the first folder above
        // them whose names differ: "Acme Fonts (Dropbox)" and "Acme Fonts (Server)".
        for (_, same) in Dictionary(grouping: sources.indices, by: { sources[$0].name }) where same.count > 1 {
            let paths = same.map { sources[$0].id.split(separator: "/").map(String.init).dropLast() }
            var above = paths.map { _ in "" }
            for level in 1...(paths.map(\.count).max() ?? 1) {
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

        /// The copy a place uses for a style: one that's on, then one in use through a copy installed from
        /// it, then the newest version, then the first path.
        func better(_ a: Candidate, than b: Candidate) -> Bool {
            if a.copy.state.isActive != b.copy.state.isActive { return a.copy.state.isActive }
            if a.isInUse != b.isInUse { return a.isInUse }
            let (va, vb) = (a.copy.face.version ?? "", b.copy.face.version ?? "")
            if va != vb { return FontVersion.precedes(vb, va) }
            return a.copy.face.id < b.copy.face.id
        }
    }

    /// Turns on the place's copies and turns off the other copies of the same styles that Cicero turned on.
    /// Styles the place doesn't have stay as they are.
    public static func plan(_ source: CopySource, records: ActivationRecords, library: Library) -> CopySwitchPlan {
        var switches: [CopySwitch] = []
        var leavesOtherCopiesOn = false
        var leaving = Set<String>()
        for choice in source.choices {
            let all = [FaceCopy(choice.style)] + choice.style.copies
            let chosen = choice.copy.face.path
            // The chosen copy stays on, and so does a copy Cicero installed from it.
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
        // Whatever else is on from the files going off goes off with them.
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

    /// Copies Cicero can turn on and off for a place: not macOS's, an app's or Adobe's, and in a Fonts folder
    /// only when Cicero installed it there.
    static func isChoosable(_ copy: FaceCopy, installedFrom origin: String?, locations: Locations) -> Bool {
        let path = copy.face.path
        guard copy.app == nil, !ActivationEngine.isProtected(path) else { return false }
        switch copy.state {
        case .active(.fontsFolder): return origin != nil
        case .active(.inPlace), .active(.temporary): return true
        case .inactive:
            // One macOS has off in a Fonts folder isn't Cicero's to turn on from there.
            return !path.hasPrefix(locations.userFonts.path + "/") && !path.hasPrefix(locations.allUsersFonts.path + "/")
        default: return false
        }
    }

    /// Copies Cicero turned on, which it turns off again when another copy takes over. Not those an
    /// application set has on while its apps are open: the set turns them on again.
    static func isManaged(_ copy: FaceCopy, records: ActivationRecords) -> Bool {
        guard copy.app == nil else { return false }
        switch copy.state.source {
        case .inPlace, .temporary(.untilQuit): return true
        case .fontsFolder: return records.installedCopies[copy.face.path] != nil
        default: return false
        }
    }

    /// Where a copy is, as Use Copy From lists it: the place's key (the folder's path) and its folders from the
    /// watched folder down ("Clients", "Acme").
    public struct Place: Hashable, Sendable {
        public let key: String
        public let location: [String]
    }

    /// The places copies are in, given the style each is a copy of and its folder (for a copy Cicero installed,
    /// the folder of its original), in the same order. Each watched folder is a place, unless copies of one
    /// style are in different folders inside it: then it parts where their paths do. Two copies of a style in
    /// one place are spares; copies in different places are for choosing between.
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

    /// A folder by the outermost watched folder it's in and the folders below that, down to it; Cicero's
    /// Deactivated folder; else the folder itself.
    struct Location {
        /// The watched folder's path.
        var root: String
        var name: String
        /// The folders between the root and the folder: ["Acme", "Fonts"].
        var below: [String]
    }

    static func location(of folder: String, folders: [WatchedFolder], locations: Locations) -> Location {
        let deactivated = locations.deactivated.path
        if folder == deactivated || folder.hasPrefix(deactivated + "/") { return Location(root: deactivated, name: "Deactivated", below: []) }
        let root = folders.filter { folder == $0.path || folder.hasPrefix($0.path + "/") }.min { $0.path.count < $1.path.count }
        guard let root else { return Location(root: folder, name: (folder as NSString).lastPathComponent, below: []) }
        return Location(root: root.path, name: root.displayName, below: folder.dropFirst(root.path.count).split(separator: "/").map(String.init))
    }
}

/// Font versions as their files give them ("Version 2.001", "Version 5.01.2"), compared by number.
public enum FontVersion {
    /// "Version 2.001" → [2.001], "Version 5.01.2" → [5.01, 2]; empty when there's no number.
    public static func number(_ version: String) -> [Double] {
        let parts = version.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }.split(separator: ".")
        guard let major = parts.first else { return [] }
        return [Double(parts.count > 1 ? "\(major).\(parts[1])" : String(major)) ?? 0] + parts.dropFirst(2).compactMap { Double($0) }
    }

    /// Whether `a` is older than `b`.
    public static func precedes(_ a: String, _ b: String) -> Bool {
        number(a).lexicographicallyPrecedes(number(b))
    }
}

extension FontFace {
    /// The same face in a byte-for-byte copy of its file elsewhere.
    func at(_ path: String) -> FontFace {
        FontFace(
            id: FaceID(path: path, index: id.index), postScriptName: postScriptName, familyName: familyName, styleName: styleName,
            fullName: fullName, weight: weight, isItalic: isItalic, isMonospaced: isMonospaced, familyClass: familyClass,
            panose: panose, letterShape: letterShape, manufacturer: manufacturer, version: version, designer: designer, vendorID: vendorID, weightAxis: weightAxis,
            width: width, axes: axes, year: year, embedding: embedding, features: features
        )
    }
}
