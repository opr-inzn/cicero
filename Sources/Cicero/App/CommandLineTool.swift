import AppKit
import CiceroCore
import Observation

/// The `cicero` command-line tool, in the bundle at Contents/Helpers/cicero, so it's always the app's own version.
/// Install cicero CLI links it into /usr/local/bin, which Terminal's search path has, with an administrator's
/// password when that folder needs one. The menu item says when it's installed, and installing ends with a dialog, not a
/// toast: the item is used from the menu bar, often with no Library window open to show one.
enum CommandLineTool {
    /// Whether /usr/local/bin/cicero is a link to this Cicero's tool, for the menu item. Checked again as Cicero comes
    /// to the front, as Terminal or another Cicero may have changed the link meanwhile.
    @Observable
    final class State {
        static let shared = State()
        private(set) var installed = false

        private init() {
            refresh()
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { State.shared.refresh() } }
        }

        func refresh() {
            let installed = tool.map { linked == $0.path } ?? false
            if installed != self.installed { self.installed = installed }
        }
    }

    enum Outcome { case installed, cancelled, failed }

    /// Where the link goes.
    nonisolated static let link = URL(fileURLWithPath: "/usr/local/bin/cicero")

    /// The tool in the bundle that's running; nil in a build without it (swift run).
    static var tool: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cicero")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// What the link points to now, if it's a link.
    nonisolated static var linked: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    /// Links the tool into /usr/local/bin, asking first to replace a file there that isn't a link to it, and from a copy
    /// outside the Applications folder, which a link would stop working for once it's moved or the disk image goes.
    static func install(model: AppModel) {
        guard let tool else { return model.showToast("This build of Cicero has no cicero CLI") }
        guard ApplicationsFolder.isInApplicationsFolder else {
            return ApplicationsFolder.offerToMove(forOpenAtLogin: false)
        }
        if linked == tool.path { return showInstalled() }
        if FileManager.default.fileExists(atPath: link.path) || linked != nil {
            let alert = NSAlert()
            alert.messageText = "Replace the cicero CLI?"
            alert.informativeText = "\(link.path) is there already\(linked.map { ", a link to \($0)" } ?? ""). Replace it with this Cicero’s CLI?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            let outcome = await makeLink(to: tool)
            State.shared.refresh()
            switch outcome {
            case .installed: showInstalled()
            case .cancelled: break  // The user cancelled macOS's password dialog: they know.
            case .failed:
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn’t install the cicero CLI"
                alert.informativeText = "Cicero couldn’t put a link to it in \(link.deletingLastPathComponent().path)."
                NSApp.activate()
                alert.runModal()
            }
        }
    }

    /// The dialog after installing, and when it's chosen again once installed.
    private static func showInstalled() {
        let alert = NSAlert()
        alert.messageText = "The cicero CLI is installed"
        alert.informativeText = "In Terminal, type cicero --help."
        NSApp.activate()
        alert.runModal()
    }

    /// Makes the link, without a password when the user may write to /usr/local/bin (as Homebrew on Intel Macs lets
    /// them), else once macOS has asked for an administrator's password. Installed when the link points to the tool
    /// after; cancelled when the user cancelled the password dialog.
    @concurrent
    nonisolated private static func makeLink(to tool: URL) async -> Outcome {
        let fm = FileManager.default
        let folder = link.deletingLastPathComponent().path
        if fm.isWritableFile(atPath: folder) {
            try? fm.removeItem(at: link)
            try? fm.createSymbolicLink(at: link, withDestinationURL: tool)
        } else {
            let script = "/bin/mkdir -p \(quoted(folder)) && /bin/ln -sfn \(quoted(tool.path)) \(quoted(link.path))"
            let source = "do shell script \(literal(script)) with prompt \(literal("Cicero wants to install the cicero CLI in \(folder).")) with administrator privileges"
            let cancelled = await MainActor.run {
                var error: NSDictionary?
                _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
                return error?[NSAppleScript.errorNumber] as? Int == -128  // userCanceledErr
            }
            if cancelled { return .cancelled }
        }
        return linked == tool.path ? .installed : .failed
    }

    /// A path as one shell word.
    nonisolated private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Text as an AppleScript string.
    nonisolated private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
