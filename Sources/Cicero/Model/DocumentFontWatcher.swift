import AppKit
import CiceroCore

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

    /// The apps asked which fonts their documents use.
    static let bundleIDs = Set(App.allCases.map(\.rawValue))

    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var polling: Task<Void, Never>?
    /// While the screens sleep, no one opens a document, and asking would keep waking the app.
    private var isAsleep = false
    /// Apps that didn't let Cicero ask them (Automation in Privacy & Security), left alone until Cicero opens again.
    private var refused: Set<App> = []
    /// What each app's documents used when it was asked last, so the same answer isn't matched again.
    private var lastFonts: [App: [DocumentFont]] = [:]
    /// Illustrator and Photoshop files read before → when they were last saved then, and their fonts.
    private var files: [String: (saved: Date?, fonts: [DocumentFont])] = [:]
    /// Often: asking takes a few milliseconds, and costs the app hardly any time.
    private static let interval: Duration = .milliseconds(500)

    func start(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        let changes: [(Notification.Name, asleep: Bool?)] = [
            (NSWorkspace.didActivateApplicationNotification, nil),
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
        ]
        observers = changes.map { name, asleep in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if let asleep { self?.isAsleep = asleep }
                    self?.frontmostChanged()
                }
            }
        }
        frontmostChanged()
    }

    /// The setting changed, in Settings or the menu bar's menu.
    func settingChanged() {
        lastFonts = [:]
        if model?.data.activatesDocumentFonts == false { model?.appSets.forgetRequests() }
        frontmostChanged()
    }

    private func frontmostChanged() {
        polling?.cancel()
        polling = nil
        guard let model, model.data.activatesDocumentFonts, !isAsleep, let running = NSWorkspace.shared.frontmostApplication,
              let app = running.bundleIdentifier.flatMap(App.init), !refused.contains(app)
        else { return }
        // Matched again each time it comes to the front: the app may have been opened again since.
        lastFonts[app] = nil
        let pid = running.processIdentifier
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ask(app, pid)
                try? await Task.sleep(for: Self.interval, tolerance: .milliseconds(100))
            }
        }
    }

    // MARK: Asking

    private func ask(_ app: App, _ pid: pid_t) async {
        let answer: [DocumentFont]
        switch await Self.ask(app, pid) {
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

    /// The fonts the app's open documents use, or their files; nil when it won't let Cicero ask. Sends the Apple Events
    /// itself, to the app's process: AppleScript would spend most of the time compiling, and both compiling and running
    /// a script open an app that has quit. Asks off the main thread: an app that's busy can take its time to answer.
    @concurrent
    private static func ask(_ app: App, _ pid: pid_t) async -> Answer? {
        let documents = every("docu", of: .null())
        do {
            switch app {
            case .inDesign:
                // Codes from InDesign itself, which has no dictionary file.
                let fonts = every("FonT", of: documents)
                let (n, f, s) = try (
                    strings(get(property("fPSN", of: fonts), from: pid)),
                    strings(get(property("fFam", of: fonts), from: pid)),
                    strings(get(property("fSty", of: fonts), from: pid))
                )
                guard n.count == f.count, n.count == s.count else { return .fonts([]) }
                return .fonts(n.indices.map { DocumentFont(postScriptName: n[$0], family: f[$0], style: s[$0]) })
            case .illustrator, .photoshop:
                // Files are read as last saved. Illustrator names an unsaved one like "/Untitled-1".
                let filePath = app == .illustrator ? "aiFS" : "Dpth"
                func paths(_ result: NSAppleEventDescriptor) -> [String] {
                    items(result).compactMap { $0.fileURLValue?.path }.filter { FileManager.default.fileExists(atPath: $0) }
                }
                do {
                    return .files(paths(try get(property(filePath, of: documents), from: pid)))
                } catch let error as NSError where error.code != errAEEventNotPermitted {
                    // Photoshop fails them all for one that's unsaved: then each document is asked in turn.
                    let each = items(try get(documents, from: pid))
                    return .files(each.flatMap { (try? paths(get(property(filePath, of: $0), from: pid))) ?? [] })
                }
            }
        } catch let error as NSError where error.code == errAEEventNotPermitted {
            return nil
        } catch {
            // Quit, busy for longer than the timeout, or with no documents.
            return app == .inDesign ? .fonts([]) : .files([])
        }
    }

    /// What the specifier points to, from the app's process, waiting up to 10 s; throws the app's error. macOS asks the
    /// user first whether Cicero may, the first time.
    nonisolated private static func get(_ specifier: NSAppleEventDescriptor, from pid: pid_t) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(specifier, forKeyword: keyDirectObject)
        let reply = try event.sendEvent(options: .defaultOptions, timeout: 10)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, error != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .list()
    }

    /// `every <class> of <container>`, with the class's code from the app's dictionary.
    nonisolated private static func every(_ type: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = DescType(kAEAll)
        let data = NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal), bytes: &all, length: 4)!
        return specifier(of: code(type), form: DescType(formAbsolutePosition), data: data, in: container)
    }

    /// `<property> of <container>`.
    nonisolated private static func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(of: DescType(typeProperty), form: DescType(formPropertyID), data: NSAppleEventDescriptor(typeCode: code(name)), in: container)
    }

    nonisolated private static func specifier(
        of type: DescType, form: DescType, data: NSAppleEventDescriptor, in container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: type), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
    }

    nonisolated private static func code(_ text: String) -> DescType {
        text.utf8.reduce(0) { $0 << 8 | DescType($1) }
    }

    /// The items in a result, in lists in lists too: InDesign gives one list per document.
    nonisolated private static func items(_ descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard descriptor.descriptorType == typeAEList else { return [descriptor] }
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).flatMap { descriptor.atIndex($0).map(items) ?? [] }
    }

    /// The text of each item, empty for one that has none, such as a font with no style name, so that InDesign's
    /// lists still line up.
    nonisolated private static func strings(_ descriptor: NSAppleEventDescriptor) -> [String] {
        items(descriptor).map { $0.stringValue ?? "" }
    }
}
