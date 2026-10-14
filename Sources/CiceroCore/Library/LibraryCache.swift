import Foundation

/// The library the last scan built, saved for the next launch, so the window opens with the fonts in it
/// instead of waiting for that launch's first scan. Written like the face cache, which it takes faces from,
/// and for the same reason: it's read before the window appears.
enum LibraryCache {
    private static let magic: UInt32 = 0x4243_4C43  // "CLCB"
    private static let version: UInt32 = 1

    private struct SavedFamily: Sendable {
        var name: String
        var manufacturer: String?
        var folderIDs: Set<UUID>
        var faces: [LibraryFace]
    }

    static func encode(_ library: Library) -> Data {
        var writer = ByteWriter()
        writer.write(magic)
        writer.write(version)
        writer.write(FaceCache.version)
        writer.write(Int64(library.fingerprint))
        writer.write(UInt32(library.families.count))
        for family in library.families {
            writer.write(family.name)
            writer.write(family.manufacturer)
            writer.write(UInt32(family.folderIDs.count))
            for id in family.folderIDs { writer.write(id) }
            writer.write(UInt32(family.faces.count))
            for face in family.faces {
                writer.write(face.face.path)
                writer.write(face.face)
                writer.write(face.app)
                writer.write(face.state)
                writer.write(face.dateAdded?.timeIntervalSinceReferenceDate)
                writer.write(UInt32(face.copies.count))
                for copy in face.copies {
                    writer.write(copy.face.path)
                    writer.write(copy.face)
                    writer.write(copy.app)
                    writer.write(copy.state)
                }
            }
        }
        writer.write(library.unreadableFiles)
        writer.write(Array(library.activePaths))
        writer.write(UInt32(library.unavailableFolders.count))
        for (id, availability) in library.unavailableFolders {
            let tag: UInt8 = switch availability {
            case .notFound: 0
            case .noAccess: 1
            }
            writer.write(id)
            writer.write(tag)
        }
        writer.write(UInt32(library.onlineOnlyFiles.count))
        for (id, paths) in library.onlineOnlyFiles {
            writer.write(id)
            writer.write(paths)
        }
        writer.write(Array(library.offlineFamilies))
        return writer.data
    }

    /// nil when the data isn't a library this version saved. `current` gives a face's state now from the
    /// saved one, the face's file and the app that loads it.
    static func decode(_ data: Data, current: (FaceState, String, String?) -> FaceState = { state, _, _ in state }) -> Library? {
        data.withUnsafeBytes { buffer -> Library? in
            var reader = ByteReader(buffer: buffer)
            do {
                guard try reader.u32() == magic, try reader.u32() == version, try reader.u32() == FaceCache.version else { return nil }
                let fingerprint = Int(try reader.i64())
                // Read in one pass; making the families, most of the work, is spread over the cores after.
                var members: [SavedFamily] = []
                for _ in 0..<Int(try reader.u32()) {
                    let name = try reader.string()
                    let manufacturer = try reader.optionalString()
                    var folderIDs = Set<UUID>()
                    for _ in 0..<Int(try reader.u32()) { folderIDs.insert(try reader.uuid()) }
                    var faces: [LibraryFace] = []
                    for _ in 0..<Int(try reader.u32()) {
                        let path = try reader.string()
                        let face = try reader.face(path: path)
                        let app = try reader.optionalString()
                        let state = current(try reader.state(), path, app)
                        let dateAdded = try reader.optionalDouble().map { Date(timeIntervalSinceReferenceDate: $0) }
                        var copies: [FaceCopy] = []
                        for _ in 0..<Int(try reader.u32()) {
                            let path = try reader.string()
                            let face = try reader.face(path: path)
                            let app = try reader.optionalString()
                            copies.append(FaceCopy(face: face, state: current(try reader.state(), path, app), app: app))
                        }
                        faces.append(LibraryFace(face: face, state: state, copies: copies, dateAdded: dateAdded, app: app))
                    }
                    guard !faces.isEmpty else { return nil }
                    members.append(SavedFamily(name: name, manufacturer: manufacturer, folderIDs: folderIDs, faces: faces))
                }
                let families = members.concurrentMap { family in
                    Family(name: family.name, faces: family.faces, state: LibraryScanner.familyState(of: family.faces),
                           folderIDs: family.folderIDs, manufacturer: family.manufacturer)
                }
                let unreadable = try reader.strings()
                let activePaths = Set(try reader.strings())
                var unavailable: [UUID: FolderAvailability] = [:]
                for _ in 0..<Int(try reader.u32()) {
                    let id = try reader.uuid()
                    switch try reader.u8() {
                    case 0: unavailable[id] = .notFound
                    case 1: unavailable[id] = .noAccess
                    default: throw LibraryCacheUnknown()
                    }
                }
                var onlineOnly: [UUID: [String]] = [:]
                for _ in 0..<Int(try reader.u32()) {
                    let id = try reader.uuid()
                    onlineOnly[id] = try reader.strings()
                }
                let offline = Set(try reader.strings())
                return Library(families: families, unreadableFiles: unreadable, activePaths: activePaths, fingerprint: fingerprint,
                               unavailableFolders: unavailable, onlineOnlyFiles: onlineOnly, offlineFamilies: offline)
            } catch {
                return nil
            }
        }
    }
}

private extension ByteWriter {
    mutating func write(_ strings: [String]) {
        write(UInt32(strings.count))
        for string in strings { write(string) }
    }

    mutating func write(_ state: FaceState) {
        switch state {
        case .inactive:
            write(UInt8(0))
        case .appOnly(let app):
            write(UInt8(1))
            write(app)
        case .active(let source):
            let tag: UInt8 = switch source {
            case .macOS: 0
            case .allUsers: 1
            case .app: 2
            case .adobeFonts: 3
            case .fontsFolder: 4
            case .inPlace: 5
            case .temporary(.untilQuit): 6
            case .temporary(.whileAppsRun): 7
            case .otherApp: 8
            }
            write(UInt8(2))
            write(tag)
        }
    }
}

private extension ByteReader {
    mutating func strings() throws -> [String] {
        var strings: [String] = []
        for _ in 0..<Int(try u32()) { strings.append(try string()) }
        return strings
    }

    mutating func state() throws -> FaceState {
        switch try u8() {
        case 0: return .inactive
        case 1: return .appOnly(try string())
        case 2:
            switch try u8() {
            case 0: return .active(.macOS)
            case 1: return .active(.allUsers)
            case 2: return .active(.app)
            case 3: return .active(.adobeFonts)
            case 4: return .active(.fontsFolder)
            case 5: return .active(.inPlace)
            case 6: return .active(.temporary(.untilQuit))
            case 7: return .active(.temporary(.whileAppsRun))
            case 8: return .active(.otherApp)
            default: throw LibraryCacheUnknown()
            }
        default: throw LibraryCacheUnknown()
        }
    }
}

/// A value the library cache doesn't know, as from a damaged file.
private struct LibraryCacheUnknown: Error {}
