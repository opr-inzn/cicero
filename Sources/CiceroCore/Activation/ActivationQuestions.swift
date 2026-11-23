import Foundation

public enum ActivationQuestions {
    public static func many(for faces: [LibraryFace], title: String, temporarily: Bool, data: UserData) -> ManyActivationPrompt? {
        guard data.asksBeforeActivatingMany else { return nil }
        let families = Set(faces.map(\.face.familyName)).count
        guard families > UserData.manyFamilies else { return nil }
        return ManyActivationPrompt(title: title, faces: faces, families: families, temporarily: temporarily)
    }

    public static func movingOut(for faces: [LibraryFace], data: UserData) -> MovingOutPrompt? {
        guard data.asksBeforeMovingOutOfSharedFolders else { return nil }
        var checked: Set<String> = []
        var sharing: [String: FolderSharing] = [:]
        var shared: [(face: LibraryFace, folder: String)] = []
        for face in faces where ActivationEngine.movesOutOfAppFolder(face, records: data.records) {
            let folder = (face.face.path as NSString).deletingLastPathComponent
            if checked.insert(folder).inserted, FileManager.default.isWritableFile(atPath: folder),
               let found = ActivationEngine.sharing(ofFolder: folder) {
                sharing[folder] = found
            }
            if sharing[folder] != nil { shared.append((face, folder)) }
        }
        guard !shared.isEmpty else { return nil }
        let folders = Set(shared.map(\.folder))
        let apps = Set(shared.compactMap(\.face.app))
        return MovingOutPrompt(
            faces: faces, shared: shared.map(\.face),
            folder: folders.count == 1 ? folders.first.flatMap { path in sharing[path].map { (path: path, sharing: $0) } } : nil,
            app: apps.count == 1 ? apps.first.map(FaceState.appDescription) : nil
        )
    }
}

public struct MovingOutPrompt: Identifiable {
    public let id = UUID()
    public var faces: [LibraryFace]
    public var shared: [LibraryFace]
    public var folder: (path: String, sharing: FolderSharing)?
    public var app: String?

    public init(faces: [LibraryFace], shared: [LibraryFace], folder: (path: String, sharing: FolderSharing)?, app: String?) {
        self.faces = faces
        self.shared = shared
        self.folder = folder
        self.app = app
    }

    public var title: String {
        let name = folder.map { "“\(($0.path as NSString).lastPathComponent)”" } ?? "Shared Folders"
        if shared.count == 1, let face = shared.first {
            return "Move “\(face.face.familyName) \(face.face.styleName)” Out of \(name)?"
        }
        return "Move \(shared.count.plain) Styles Out of \(name)?"
    }

    public var message: String {
        let one = shared.count == 1
        let apps = app.map { $0 == "Adobe apps" ? "Adobe apps load" : "\($0) loads" } ?? "The apps they’re for load"
        let place = folder.map { "“\(($0.path as NSString).lastPathComponent)”" } ?? "the folders they’re in"
        let moving = "\(apps) every font in \(place), so to turn \(one ? "it" : "them") off there too, Cicero moves \(one ? "its file" : "their files") into its Inactive folder."
        guard let folder else {
            return moving + " These folders sync with a cloud service or are on a server, so the files also go away for everyone who shares them."
        }
        let name = "“\((folder.path as NSString).lastPathComponent)”"
        let files = one ? "the file also goes" : "the files also go"
        switch folder.sharing {
        case .iCloudDrive:
            return moving + " \(name) is in iCloud Drive, so \(files) away on your other devices and for anyone you share it with."
        case .cloudService(let service):
            return moving + " \(name) syncs with \(service ?? "a cloud service"), so \(files) away on the other Macs that share it."
        case .server(let server):
            return moving + " \(name) is on the server “\(server)”, so \(files) away for everyone who uses it."
        }
    }

    public var keepTitle: String? {
        let shared = Set(shared.map(\.id))
        guard self.shared.contains(where: { $0.position == .on }) || faces.contains(where: { !shared.contains($0.id) }) else { return nil }
        guard let app else { return "Keep On in Their Apps" }
        return "Keep On in \(app == "Adobe apps" ? "Adobe Apps" : app)"
    }
}

public struct ManyActivationPrompt: Identifiable {
    public let id = UUID()
    public var title: String
    public var faces: [LibraryFace]
    public var families: Int
    public var temporarily: Bool

    public init(title: String, faces: [LibraryFace], families: Int, temporarily: Bool) {
        self.title = title
        self.faces = faces
        self.families = families
        self.temporarily = temporarily
    }
}
