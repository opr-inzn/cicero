import AppKit
import CiceroCore
import Observation

enum CommandLineTool {
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
            let installed = tool.map { Link(at: link, to: $0).isMade } ?? false
            if installed != self.installed { self.installed = installed }
        }
    }

    enum Outcome { case installed, cancelled, failed }

    nonisolated struct Link: Sendable {
        let at: URL
        let to: URL
        var isMade: Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: at.path)) == to.path }
    }

    nonisolated static let prefix = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CICERO_INSTALL_PREFIX"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local")
    nonisolated static let link = prefix.appendingPathComponent("bin/cicero")
    nonisolated static let completionScripts = [
        (script: "zsh/_cicero", link: "share/zsh/site-functions/_cicero"),
        (script: "bash/cicero", link: "share/bash-completion/completions/cicero"),
        (script: "fish/cicero.fish", link: "share/fish/vendor_completions.d/cicero.fish"),
    ]

    static var tool: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cicero")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var links: [Link]? {
        let resources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        let scripts = completionScripts.map { Link(at: prefix.appendingPathComponent($0.link), to: resources.appendingPathComponent($0.script)) }
        guard let tool, scripts.allSatisfy({ FileManager.default.fileExists(atPath: $0.to.path) }) else { return nil }
        return [Link(at: link, to: tool)] + scripts
    }

    nonisolated static var linked: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    static func install(model: AppModel) {
        guard let tool, let links else { return model.showToast("This build of Cicero has no Cicero CLI") }
        guard ApplicationsFolder.isInApplicationsFolder else {
            return ApplicationsFolder.offerToMove(forOpenAtLogin: false)
        }
        if links.allSatisfy(\.isMade) {
            Task { await showInstalled() }
            return
        }
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
            case .installed: await showInstalled()
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

    private static func showInstalled() async {
        let tab = await TabCompletion.state()
        let offers = tab.map { !$0.isOn && !TabCompletion.hasLine($0.file) } ?? false
        // The file as the user knows it: in the home folder, unless their setup keeps zsh's files elsewhere.
        let place = tab.map { $0.file.deletingLastPathComponent().path == NSHomeDirectory() ? "the file .zshrc in your home folder" : $0.file.path } ?? ""
        let alert = NSAlert()
        alert.messageText = "The Cicero CLI is installed"
        alert.informativeText = "In Terminal, type cicero --help."
        if offers {
            alert.informativeText += "\n\nTab completion is off in Terminal. To turn it on, Cicero adds a line to \(place). It works in new Terminal windows."
            alert.addButton(withTitle: "Turn On Tab Completion")
            alert.addButton(withTitle: "Not Now")
        }
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, offers, let file = tab?.file else { return }
        if await TabCompletion.turnOn(file) { return }
        let failed = NSAlert()
        failed.alertStyle = .warning
        failed.messageText = "Couldn’t turn on Tab completion"
        failed.informativeText = "Add this line to \(place):\n\n\(TabCompletion.line)"
        NSApp.activate()
        failed.runModal()
    }

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

    nonisolated private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    nonisolated private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
