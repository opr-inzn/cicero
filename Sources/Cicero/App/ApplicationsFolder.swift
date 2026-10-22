import AppKit
import CiceroCore
import DiskArbitration

/// Moving Cicero into the Applications folder. Open at Login (which application sets need) points at the
/// copy that's running, and Sparkle replaces that copy, so neither works from a disk image (read-only,
/// ejected later), Downloads, or an App Translocation path (random and read-only). At launch Cicero asks
/// once to move itself, and turning on Open at Login asks again instead of adding a login item that breaks.
enum ApplicationsFolder {
    private static let dontAskKey = "applicationsFolder.dontAsk"
    /// Set when the move was for Open at Login, so the moved copy turns it on.
    private static let openAtLoginKey = "applicationsFolder.openAtLoginAfterMove"
    private static var hasCheckedAtLaunch = false

    /// The copy the user opened: where it runs from, or where it was before it was translocated. nil for a
    /// binary run from .build (swift run), which there's nothing to move for.
    private static var openedBundle: URL? {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app" ? AppLocation.originalURL(of: bundle) : nil
    }

    /// Whether Cicero runs from /Applications or ~/Applications (or from .build).
    static var isInApplicationsFolder: Bool {
        guard let bundle = openedBundle else { return true }
        return AppLocation.isInApplicationsFolder(bundle, home: .homeDirectory)
    }

    /// Offers to move Cicero, unless it's already in place or the user said not to ask again; a copy that
    /// was moved for Open at Login turns it on.
    static func checkAtLaunch(model: AppModel) {
        guard !hasCheckedAtLaunch else { return }
        hasCheckedAtLaunch = true
        let defaults = UserDefaults.standard
        if isInApplicationsFolder {
            if defaults.bool(forKey: openAtLoginKey) {
                defaults.removeObject(forKey: openAtLoginKey)
                _ = LoginItem.set(true, model: model)
            }
        } else if !defaults.bool(forKey: dontAskKey) {
            // Once the window is up, rather than in the middle of a view update.
            Task { offerToMove(forOpenAtLogin: false) }
        }
    }

    /// Asks to move Cicero into the Applications folder and, if the user agrees, moves it, quits and opens
    /// the moved copy. The prompt for Open at Login has no "Don’t ask again": the user just asked for it.
    static func offerToMove(forOpenAtLogin: Bool) {
        let alert = NSAlert()
        alert.messageText = "Move Cicero to the Applications folder?"
        alert.informativeText = "App folders, opening at login and updates work only when Cicero is in the Applications folder."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Do Not Move")
        if !forOpenAtLogin {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t ask again"
        }
        let response = alert.runModal()
        if !forOpenAtLogin, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: dontAskKey)
        }
        guard response == .alertFirstButtonReturn else { return }
        do {
            try move(forOpenAtLogin: forOpenAtLogin)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn’t move Cicero to the Applications folder."
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    private static func move(forOpenAtLogin: Bool) throws {
        let running = Bundle.main.bundleURL
        let original = AppLocation.originalURL(of: running)
        let volume = try? original.resourceValues(forKeys: [.volumeURLKey, .volumeIsReadOnlyKey])
        let move = AppLocation.move(
            from: original, volume: volume?.volume, volumeIsReadOnly: volume?.volumeIsReadOnly ?? true,
            volumeIsDiskImage: volume?.volume.map(isDiskImage) ?? false,
            home: .homeDirectory, canWriteToApplications: FileManager.default.isWritableFile(atPath: "/Applications"))

        // A Cicero running from there quits before its copy goes to the Trash, so the moved one opens
        // instead of bringing it to the front.
        let replaced = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current && $0.bundleURL?.standardizedFileURL.path == move.destination.standardizedFileURL.path }
        replaced.forEach { $0.terminate() }

        try AppLocation.install(running, at: move.destination)
        if let original = move.originalToTrash {
            try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
        }
        if forOpenAtLogin { UserDefaults.standard.set(true, forKey: openAtLoginKey) }
        let processes = [ProcessInfo.processInfo.processIdentifier] + replaced.map(\.processIdentifier)
        try relaunch(move.destination, detaching: move.diskImageToDetach, after: processes)
        NSApp.terminate(nil)
    }

    /// Opens the moved copy once these processes have quit (waiting up to 30 seconds for each), detaching
    /// the disk image Cicero ran from first.
    private static func relaunch(_ app: URL, detaching diskImage: URL?, after processes: [pid_t]) throws {
        let script = """
            app=$1 image=$2
            shift 2
            for pid in "$@"; do
                for _ in $(seq 300); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
            done
            [ -z "$image" ] || /usr/bin/hdiutil detach "$image" -quiet
            /usr/bin/open "$app"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", app.path, diskImage?.path ?? ""] + processes.map(String.init)
        try process.run()
    }

    private static func isDiskImage(_ volume: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any]
        else { return false }
        return description[kDADiskDescriptionDeviceModelKey as String] as? String == "Disk Image"
    }
}
