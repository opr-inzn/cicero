import Foundation

/// Who else has a folder's files besides this Mac: what moving a file out of it reaches.
public enum FolderSharing: Equatable, Sendable {
    /// ~/Library/Mobile Documents, or anything else iCloud keeps, as Desktop & Documents.
    case iCloudDrive
    /// A cloud service that syncs it to other Macs and other people: Dropbox, Google Drive, OneDrive… nil when its name
    /// isn't known.
    case cloudService(String?)
    /// A server's disk, with its name.
    case server(String)
}

extension ActivationEngine {
    /// Whether deactivating `face` moves its file out of the folder the app loads it from, as `deactivate` does it: a face
    /// on in that app, not Creative Cloud's, and not out of the folder already.
    public static func movesOutOfAppFolder(_ face: LibraryFace, records: ActivationRecords) -> Bool {
        face.canDeactivate && face.app != nil && !face.isAdobeFonts && records.appFolderOrigins[face.face.path] == nil
    }

    /// Who else has the files in `folder` (see `FolderSharing`), by its path or the one symbolic links lead to; nil when
    /// they're on this Mac only. Dropbox's own folder counts where Dropbox says it is, also outside ~/Library/CloudStorage.
    public static func sharing(ofFolder folder: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> FolderSharing? {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let paths = [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path].map { $0 + "/" }
        switch cloudService(syncing: url) {
        case .iCloudDrive:
            return .iCloudDrive
        case .other:
            // Its folder in ~/Library/CloudStorage starts with its name.
            let folder = paths.lazy.compactMap { path in path.range(of: "/Library/CloudStorage/").map { path[$0.upperBound...] } }.first
            let name = folder?.prefix { $0 != "/" }.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            return .cloudService(serviceName(name))
        case nil:
            break
        }
        if dropboxFolders(home: home).contains(where: { root in paths.contains { $0.hasPrefix(root + "/") } }) {
            return .cloudService("Dropbox")
        }
        if let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeLocalizedNameKey]), values.volumeIsLocal == false {
            return .server(values.volumeLocalizedName ?? url.lastPathComponent)
        }
        return nil
    }

    /// The service's name as people know it, from the start of its folder's name in ~/Library/CloudStorage
    /// ("GoogleDrive-me@example.com"); nil when there's none.
    private static func serviceName(_ folder: String) -> String? {
        switch folder {
        case "": nil
        case "GoogleDrive": "Google Drive"
        case "OneDrive": "OneDrive"
        case "Dropbox": "Dropbox"
        case "Box": "Box"
        default: folder
        }
    }

    /// Where Dropbox keeps its folders, as it writes in ~/.dropbox/info.json: ~/Dropbox for one set up before it moved
    /// into ~/Library/CloudStorage.
    private static func dropboxFolders(home: URL) -> [String] {
        let info = home.appendingPathComponent(".dropbox/info.json")
        guard let data = try? Data(contentsOf: info),
              let accounts = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return accounts.values.compactMap { ($0 as? [String: Any])?["path"] as? String }.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }
}
