import AppKit
import CiceroCore

final class DocumentFontWatcher {
    nonisolated private enum App: String, CaseIterable {
        case inDesign = "com.adobe.InDesign"
        case illustrator = "com.adobe.illustrator"
        case photoshop = "com.adobe.Photoshop"
    }

    static let bundleIDs = Set(App.allCases.map(\.rawValue))

    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var polling: Task<Void, Never>?
    private var isAsleep = false
    private var lastFonts: [App: [DocumentFont]] = [:]
    private var matcher: (fingerprint: Int, matcher: FontMatcher)?
    private var files: [String: (saved: Date?, fonts: [DocumentFont])] = [:]
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

    func settingChanged() {
        lastFonts = [:]
        if model?.data.activatesDocumentFonts == false { model?.appSets.forgetRequests() }
        frontmostChanged()
    }

    private func frontmostChanged() {
        let previous = polling
        previous?.cancel()
        guard let model, model.data.activatesDocumentFonts, !isAsleep, let running = NSWorkspace.shared.frontmostApplication,
              let app = running.bundleIdentifier.flatMap(App.init)
        else { return }
        lastFonts[app] = nil
        let pid = running.processIdentifier
        polling = Task { [weak self] in
            await previous?.value
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
            withUnsafeCurrentTask { $0?.cancel() }
            return
        case .fonts(let fonts)?:
            answer = fonts
        case .files(let paths)?:
            answer = await fonts(inFiles: paths)
        }
        guard !Task.isCancelled, answer != lastFonts[app], let model, model.hasScanned else { return }
        lastFonts[app] = answer
        if matcher?.fingerprint != model.library.fingerprint { matcher = (model.library.fingerprint, FontMatcher(model.library)) }
        let wanted = DocumentFonts.match(answer, using: matcher!.matcher).compactMap(\.face).filter { face in
            let forApps = model.data.records.temporary[face.face.path]?.scope == .whileAppsRun
            let parked = model.data.records.appFolderOrigins[face.face.path] != nil
            return (forApps || !face.state.isActive) && (face.app == nil || parked) && !face.isAdobeFonts
        }
        if !wanted.isEmpty { model.appSets.request(Set(wanted.map(\.face.postScriptName)), for: app.rawValue) }
    }

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

    @concurrent
    private static func ask(_ app: App, _ pid: pid_t) async -> Answer? {
        let documents = every("docu", of: .null())
        do {
            switch app {
            case .inDesign:
                let fonts = every("FonT", of: documents)
                let (n, f, s) = try (
                    strings(get(property("fPSN", of: fonts), from: pid)),
                    strings(get(property("fFam", of: fonts), from: pid)),
                    strings(get(property("fSty", of: fonts), from: pid))
                )
                guard n.count == f.count, n.count == s.count else { return .fonts([]) }
                return .fonts(n.indices.map { DocumentFont(postScriptName: n[$0], family: f[$0], style: s[$0]) })
            case .illustrator, .photoshop:
                // Illustrator names an unsaved document like "/Untitled-1".
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
            return app == .inDesign ? .fonts([]) : .files([])
        }
    }

    nonisolated private static func get(_ specifier: NSAppleEventDescriptor, from pid: pid_t) throws -> NSAppleEventDescriptor {
        // To the app's process, not through AppleScript, which opens an app that has quit, both to compile a script and to run it.
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

    nonisolated private static func every(_ type: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = DescType(kAEAll)
        let data = NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal), bytes: &all, length: 4)!
        return specifier(of: code(type), form: DescType(formAbsolutePosition), data: data, in: container)
    }

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

    nonisolated private static func items(_ descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard descriptor.descriptorType == typeAEList else { return [descriptor] }
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).flatMap { descriptor.atIndex($0).map(items) ?? [] }
    }

    nonisolated private static func strings(_ descriptor: NSAppleEventDescriptor) -> [String] {
        // Empty for an item with no text, such as a font with no style name, so InDesign's lists still line up.
        items(descriptor).map { $0.stringValue ?? "" }
    }
}

// MARK: - The document in front

extension DocumentFontWatcher {
    nonisolated enum FrontDocument: Sendable {
        case file(URL)
        case fonts([DocumentFont], name: String)
    }

    @concurrent
    static func frontDocument(ofApp bundleID: String, pid: pid_t) async throws -> FrontDocument? {
        func file(_ path: String, of document: NSAppleEventDescriptor) throws -> FrontDocument? {
            let result = try get(property(path, of: document), from: pid)
            // Illustrator's file URL has no scheme, so it isn't one: the path, made into one again.
            guard let path = result.fileURLValue?.path ?? result.stringValue else { return nil }
            let url = URL(fileURLWithPath: path)
            guard DocumentFonts.fileExtensions.contains(url.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            return .file(url)
        }
        // The first time, macOS asks the user whether Cicero may, and this waits for the answer: the event itself would give up after its timeout and take the question away with it.
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        if let address = target.aeDesc,
           AEDeterminePermissionToAutomateTarget(address, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true) == errAEEventNotPermitted {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
        }
        do {
            switch bundleID {
            case App.inDesign.rawValue:
                let document = property("pacd", of: .null())
                let fonts = every("FonT", of: document)
                let (n, f, s) = try (
                    strings(get(property("fPSN", of: fonts), from: pid)),
                    strings(get(property("fFam", of: fonts), from: pid)),
                    strings(get(property("fSty", of: fonts), from: pid))
                )
                guard n.count == f.count, n.count == s.count else { return nil }
                let name = (try? get(property("pnam", of: document), from: pid).stringValue) ?? "InDesign document"
                return .fonts(n.indices.map { DocumentFont(postScriptName: n[$0], family: f[$0], style: s[$0]) }, name: name)
            case App.illustrator.rawValue:
                return try file("aiFS", of: property("aiAD", of: .null()))
            case App.photoshop.rawValue:
                return try file("Dpth", of: property("pADc", of: .null()))
            case "com.adobe.Acrobat.Pro", "com.adobe.Reader":
                return try file("pfal", of: property("padc", of: .null()))
            default:
                var first: Int32 = 1
                let index = NSAppleEventDescriptor(descriptorType: DescType(typeSInt32), bytes: &first, length: 4)!
                let window = specifier(of: code("cwin"), form: DescType(formAbsolutePosition), data: index, in: .null())
                return try file("ppth", of: property("docu", of: window))
            }
        } catch let error as NSError where error.code == errAEEventNotPermitted {
            throw error
        } catch {
            return nil
        }
    }
}

