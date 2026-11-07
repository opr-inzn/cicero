import AppKit
import CiceroCore

/// The `cicero` command-line tool, in the bundle at Contents/Helpers/cicero, so it's always the app's own version.
/// Install Command-Line links it into /usr/local/bin, which Terminal's search path has, with an administrator's
/// password when that folder needs one.
enum CommandLineTool {
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
        guard let tool else { return model.showToast("This build of Cicero has no command-line tool") }
        guard ApplicationsFolder.isInApplicationsFolder else {
            return ApplicationsFolder.offerToMove(forOpenAtLogin: false)
        }
        if linked == tool.path { return model.showToast("The cicero command is installed. In Terminal, type cicero --help") }
        if FileManager.default.fileExists(atPath: link.path) || linked != nil {
            let alert = NSAlert()
            alert.messageText = "Replace the cicero Command?"
            alert.informativeText = "\(link.path) is there already\(linked.map { ", a link to \($0)" } ?? ""). Replace it with this Cicero’s command?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            if await makeLink(to: tool) {
                model.showToast("Installed the cicero command. In Terminal, type cicero --help")
            } else {
                model.showToast("Couldn’t install the cicero command")
            }
        }
    }

    /// Makes the link, without a password when the user may write to /usr/local/bin (as Homebrew on Intel Macs lets
    /// them), else once macOS has asked for an administrator's password. True when the link points to the tool after.
    @concurrent
    nonisolated private static func makeLink(to tool: URL) async -> Bool {
        let fm = FileManager.default
        let folder = link.deletingLastPathComponent().path
        if fm.isWritableFile(atPath: folder) {
            try? fm.removeItem(at: link)
            try? fm.createSymbolicLink(at: link, withDestinationURL: tool)
        } else {
            let script = "/bin/mkdir -p \(quoted(folder)) && /bin/ln -sfn \(quoted(tool.path)) \(quoted(link.path))"
            let source = "do shell script \(literal(script)) with prompt \(literal("Cicero wants to install the cicero command in \(folder).")) with administrator privileges"
            await MainActor.run {
                var error: NSDictionary?
                _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            }
        }
        return linked == tool.path
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
