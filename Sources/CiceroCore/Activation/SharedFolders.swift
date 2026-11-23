import Foundation

public enum FolderSharing: Equatable, Sendable {
    case iCloudDrive
    case cloudService(String?)
    case server(String)
}

extension ActivationEngine {
    public static func movesOutOfAppFolder(_ face: LibraryFace, records: ActivationRecords) -> Bool {
        face.canDeactivate && face.app != nil && !face.isAdobeFonts && records.appFolderOrigins[face.face.path] == nil
    }

    public static func sharing(ofFolder folder: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> FolderSharing? {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let paths = [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path].map { $0 + "/" }
        switch cloudService(syncing: url) {
        case .iCloudDrive:
            return .iCloudDrive
        case .other:
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

    private static func dropboxFolders(home: URL) -> [String] {
        let info = home.appendingPathComponent(".dropbox/info.json")
        guard let data = try? Data(contentsOf: info),
              let accounts = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return accounts.values.compactMap { ($0 as? [String: Any])?["path"] as? String }.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }
}
