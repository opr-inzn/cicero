import AppKit
import CiceroCore
import Synchronization

/// Turns on the fonts that documents open in InDesign, Illustrator and Photoshop use, while the app is open. None of
/// them asks macOS for a font a document uses, so while one of them is in front Cicero asks it, over Apple Events,
/// twice a second: InDesign for its documents' fonts, Illustrator and Photoshop for their documents' files, whose
/// fonts `DocumentFonts` reads. The ones the library has and are off go to `AppSetWatcher`, which keeps them on until
/// the app quits. InDesign and Illustrator answer while their Missing Fonts dialog is open, and take up the fonts once
/// it's closed; Photoshop shows none, and takes them up within seconds.
final class DocumentFontWatcher {
    nonisolated private enum App: String, CaseIterable {
        case inDesign = "com.adobe.InDesign"
        case illustrator = "com.adobe.illustrator"
        case photoshop = "com.adobe.Photoshop"
    }

    private weak var model: AppModel?
    private var observer: NSObjectProtocol?
    private var polling: Task<Void, Never>?
    /// Apps that didn't let Cicero ask them (Automation in Privacy & Security), left alone until Cicero opens again.
    private var refused: Set<App> = []
    /// What each app's documents used when it was asked last, so the same answer isn't matched again.
    private var lastFonts: [App: [DocumentFont]] = [:]
    /// Illustrator and Photoshop files read before → when they were last saved then, and their fonts.
    private var files: [String: (saved: Date?, fonts: [DocumentFont])] = [:]
    /// Often: once an app's script is compiled, asking takes a few milliseconds.
    private static let interval: Duration = .milliseconds(500)

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.frontmostChanged() }
        }
        frontmostChanged()
    }

    /// The switch in Settings changed.
    func settingChanged() {
        lastFonts = [:]
        if model?.data.activatesDocumentFonts == false { model?.appSets.forgetRequests() }
        frontmostChanged()
    }

    private func frontmostChanged() {
        polling?.cancel()
        polling = nil
        guard let model, model.data.activatesDocumentFonts,
              let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier.flatMap(App.init), !refused.contains(app)
        else { return }
        // Matched again each time it comes to the front: the app may have been opened again since.
        lastFonts[app] = nil
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ask(app)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    // MARK: Asking

    private func ask(_ app: App) async {
        let answer: [DocumentFont]
        switch await Self.ask(app) {
        case nil:
            refused.insert(app)
            polling?.cancel()
            return
        case .fonts(let fonts)?:
            answer = fonts
        case .files(let paths)?:
            answer = await fonts(inFiles: paths)
        }
        guard !Task.isCancelled, answer != lastFonts[app], let model, model.hasScanned else { return }
        lastFonts[app] = answer
        // Ones on for another app's documents or a set too, so they stay on for this one when that app quits.
        let wanted = DocumentFonts.match(answer, in: model.library).compactMap(\.face).filter { face in
            let forApps = model.data.records.temporary[face.face.path]?.scope == .whileAppsRun
            return (forApps || !face.state.isActive) && face.app == nil && !face.isAdobeFonts
        }
        if !wanted.isEmpty { model.appSets.request(Set(wanted.map(\.face.postScriptName)), for: app.rawValue) }
    }

    /// The fonts the files use, read again only once a file's been saved since.
    private func fonts(inFiles paths: [String]) async -> [DocumentFont] {
        var fonts: [DocumentFont] = []
        for path in paths {
            let saved = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            if let file = files[path], file.saved == saved {
                fonts += file.fonts
            } else {
                let read = await Self.read(path)
                files[path] = (saved, read)
                fonts += read
            }
        }
        files = files.filter { paths.contains($0.key) }
        return fonts
    }

    @concurrent
    private static func read(_ path: String) async -> [DocumentFont] {
        (try? DocumentFonts.read(URL(fileURLWithPath: path))) ?? []
    }

    nonisolated private enum Answer {
        case fonts([DocumentFont])
        case files([String])
    }

    /// The fonts the app's open documents use, or their files; nil when it won't let Cicero ask. Asks off the main
    /// thread: an app that's busy can take its time to answer.
    @concurrent
    private static func ask(_ app: App) async -> Answer? {
        switch app {
        case .inDesign:
            guard let lists = run(app, { result in (1...3).map { strings(result.atIndex($0) ?? .list()) } })
            else { return nil }
            let (n, f, s) = (lists[0], lists[1], lists[2])
            guard n.count == f.count, n.count == s.count else { return .fonts([]) }
            return .fonts(n.indices.map { DocumentFont(postScriptName: n[$0], family: f[$0], style: s[$0]) })
        case .illustrator, .photoshop:
            return run(app, strings).map { .files($0) }
        }
    }

    /// What the app is asked, only while it's open: telling an app that has quit opens it again.
    nonisolated private static func source(_ app: App) -> String {
        let ask = switch app {
        case .inDesign:
            // One list per document in each.
            "return {PostScript name of fonts of documents, font family of fonts of documents, font style name of fonts of documents}"
        case .illustrator, .photoshop:
            // Unsaved documents have no file, and files are read as last saved.
            """
            set paths to {}
            repeat with i from 1 to count documents
                try
                    set end of paths to POSIX path of (file path of document i as alias)
                end try
            end repeat
            return paths
            """
        }
        return """
            if application id "\(app.rawValue)" is running then
                tell application id "\(app.rawValue)"
                    \(ask)
                end tell
            end if
            return {}
            """
    }

    /// Each app's script, kept once it has run: compiling it takes most of the time asking does. One runs at a time.
    nonisolated private static let scripts = Mutex<[App: NSAppleScript]>([:])

    /// Runs the app's script and reads its result: read from an empty list when the app isn't open or the script
    /// fails, nil only when macOS refuses to let Cicero send the app Apple Events. Asks the user first, the first time.
    nonisolated private static func run<Result: Sendable>(_ app: App, _ read: (NSAppleEventDescriptor) -> Result) -> Result? {
        // Compiling a script for an app that isn't open opens it too, to look up its words.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue).isEmpty else { return read(.list()) }
        return scripts.withLock { scripts in
            guard let script = scripts[app] ?? NSAppleScript(source: "with timeout of 10 seconds\n\(source(app))\nend timeout")
            else { return read(.list()) }
            var error: NSDictionary?
            // Fails with an error rather than a result, though Swift sees one either way.
            let result = script.executeAndReturnError(&error)
            if let error {
                // Compiled again next time, in case the app quit.
                scripts[app] = nil
                // errAEEventNotPermitted
                return error[NSAppleScript.errorNumber] as? Int == -1743 ? nil : read(.list())
            }
            scripts[app] = script
            return read(result)
        }
    }

    /// The text in a result, in lists in lists too: InDesign gives one list per document.
    nonisolated private static func strings(_ descriptor: NSAppleEventDescriptor) -> [String] {
        guard descriptor.descriptorType == typeAEList else { return descriptor.stringValue.map { [$0] } ?? [] }
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).flatMap { descriptor.atIndex($0).map(strings) ?? [] }
    }
}
