import AppKit
import CiceroCore
import Observation

/// The `cicero` command-line tool, in the bundle at Contents/Helpers/cicero, so it's always the app's own version.
/// Install Cicero CLI links it into /usr/local/bin, which Terminal's search path has, and its zsh completion script
/// (Contents/Resources/zsh/_cicero) into /usr/local/share/zsh/site-functions, which zsh's is, with one administrator's
/// password when either folder needs one. Both are links into the bundle, so an update changes them with the app. The
/// menu item says when they're installed, and installing ends with a dialog, not a toast: the item is used from the
/// menu bar, often with no Library window open to show one.
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

        /// Both links: a CLI installed before there was a completion script reads as not installed, so choosing the
        /// item again adds the script.
        func refresh() {
            let installed = links.map { links in links.allSatisfy(\.isMade) } ?? false
            if installed != self.installed { self.installed = installed }
        }
    }

    enum Outcome { case installed, cancelled, failed }

    /// A link to make, and the file in the bundle it points to.
    nonisolated struct Link: Sendable {
        let at: URL
        let to: URL
        var isMade: Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: at.path)) == to.path }
    }

    /// Where the links go: /usr/local, or for the E2E tests the folder in CICERO_INSTALL_PREFIX, which they may write to.
    nonisolated static let prefix = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CICERO_INSTALL_PREFIX"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local")
    nonisolated static let link = prefix.appendingPathComponent("bin/cicero")
    nonisolated static let completionLink = prefix.appendingPathComponent("share/zsh/site-functions/_cicero")

    /// The tool in the bundle that's running; nil in a build without it (swift run).
    static var tool: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cicero")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// The tool's link and its completion script's; nil in a build without them.
    static var links: [Link]? {
        let script = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/zsh/_cicero")
        guard let tool, FileManager.default.fileExists(atPath: script.path) else { return nil }
        return [Link(at: link, to: tool), Link(at: completionLink, to: script)]
    }

    /// What the link points to now, if it's a link.
    nonisolated static var linked: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    /// Links the tool and its completion script, asking first to replace a file in /usr/local/bin that isn't a link to
    /// this tool, and from a copy outside the Applications folder, which a link would stop working for once it's moved
    /// or the disk image goes. A completion script there that isn't this one's goes without asking: it's for the cicero
    /// being replaced, or for none.
    static func install(model: AppModel) {
        guard let tool, let links else { return model.showToast("This build of Cicero has no Cicero CLI") }
        guard ApplicationsFolder.isInApplicationsFolder else {
            return ApplicationsFolder.offerToMove(forOpenAtLogin: false)
        }
        if links.allSatisfy(\.isMade) { return showInstalled() }
        if linked != tool.path, FileManager.default.fileExists(atPath: link.path) || linked != nil {
            let alert = NSAlert()
            alert.messageText = "Replace the Cicero CLI?"
            alert.informativeText = "\(link.path) is there already\(linked.map { ", a link to \($0)" } ?? ""). Replace it with this Cicero’s CLI?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            let outcome = await make(links.filter { !$0.isMade })
            State.shared.refresh()
            switch outcome {
            case .installed: showInstalled()
            case .cancelled: break  // The user cancelled macOS's password dialog: they know.
            case .failed:
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn’t install the Cicero CLI"
                alert.informativeText = "Cicero couldn’t put links to it in \(prefix.path)."
                NSApp.activate()
                alert.runModal()
            }
        }
    }

    /// The dialog after installing, and when it's chosen again once installed.
    private static func showInstalled() {
        let alert = NSAlert()
        alert.messageText = "The Cicero CLI is installed"
        alert.informativeText = "In Terminal, type cicero --help."
        NSApp.activate()
        alert.runModal()
    }

    /// Makes the links, without a password in the folders the user may write to (as Homebrew on Intel Macs lets them
    /// write to /usr/local/bin), the others all at once after macOS has asked for an administrator's password. Installed
    /// when every link points into the bundle after; cancelled when the user cancelled the password dialog.
    @concurrent
    nonisolated private static func make(_ links: [Link]) async -> Outcome {
        let fm = FileManager.default
        var needPassword: [Link] = []
        for link in links {
            let folder = link.at.deletingLastPathComponent()
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.isWritableFile(atPath: folder.path) {
                try? fm.removeItem(at: link.at)
                try? fm.createSymbolicLink(at: link.at, withDestinationURL: link.to)
            } else {
                needPassword.append(link)
            }
        }
        if !needPassword.isEmpty {
            let script = needPassword.map {
                "/bin/mkdir -p \(quoted($0.at.deletingLastPathComponent().path)) && /bin/ln -sfn \(quoted($0.to.path)) \(quoted($0.at.path))"
            }.joined(separator: " && ")
            let source = "do shell script \(literal(script)) with prompt \(literal("Cicero wants to install its CLI in \(prefix.path).")) with administrator privileges"
            let cancelled = await MainActor.run {
                var error: NSDictionary?
                _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
                return error?[NSAppleScript.errorNumber] as? Int == -128  // userCanceledErr
            }
            if cancelled { return .cancelled }
        }
        return links.allSatisfy(\.isMade) ? .installed : .failed
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
