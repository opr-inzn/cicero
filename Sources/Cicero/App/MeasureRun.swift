#if CICERO_MEASURE
import AppKit
import CiceroCore
import CoreText

enum MeasureRun {
    private static var task: Task<Void, Never>?

    static var isAsked: Bool {
        ProcessInfo.processInfo.environment["CICERO_MEASURE_RUN"] == "1" && Measurements.isRecording
    }

    static func startIfAsked(model: AppModel, preview: PreviewSettings) {
        Measurements.watchMainThread()
        guard isAsked, task == nil else { return }
        // In front: macOS draws a window that other windows cover less often, which would skew every step.
        NSApp.activate()
        TextEditingKeys.mainWindow?.makeKeyAndOrderFront(nil)
        task = Task {
            await run(model: model, preview: preview)
            Measurements.count("run.end")
            Measurements.flush()
            NSApp.terminate(nil)
        }
    }

    private static func run(model: AppModel, preview: PreviewSettings) async {
        await launchStep("launch.window")
        guard await until(minutes: 30, { model.hasScanned }) else { return Measurements.count("run.failed", detail: "no scan") }
        await launchStep("launch.firstScan", detail: "\(model.library.families.count) families")
        guard await until(minutes: 60, { model.measuredLibraries > 0 }) else { return Measurements.count("run.failed", detail: "not indexed") }
        await launchStep("launch.indexed")
        _ = await MainSettle.wait(quiet: .seconds(1), limit: .seconds(30))
        if ProcessInfo.processInfo.environment["CICERO_MEASURE_ONLY"] == "launch" { return }

        let defaults = UserDefaults.standard
        defaults.set(BrowserMode.grid.rawValue, forKey: "browser.mode")
        model.selection = .all
        _ = await MainSettle.wait()

        let only = ProcessInfo.processInfo.environment["CICERO_MEASURE_ONLY"]
        if only == "activate-kill" {
            guard let location = model.data.folders.first?.id else { return Measurements.count("run.failed", detail: "no location") }
            let families = Array(model.library.families.filter { $0.folderIDs.contains(location) && $0.position == .off }.prefix(3))
            model.activate(families)
            await model.enqueued { _ in }
            Measurements.count("activated", detail: families.map(\.name).joined(separator: ", "))
            Measurements.flush()
            kill(getpid(), SIGKILL)
        }
        if only == "quit-temp" {
            guard let location = model.data.folders.first?.id else { return Measurements.count("run.failed", detail: "no location") }
            let count = Int(ProcessInfo.processInfo.environment["CICERO_MEASURE_COUNT"] ?? "") ?? 3
            let families = Array(model.library.families.filter { $0.folderIDs.contains(location) && $0.position == .off }.prefix(count))
            model.activateTemporarily(families.flatMap(\.faces), confirmed: true)
            await settled(model)
            let on = families.filter { model.family($0.id)?.position == .on }.count
            Measurements.count("onUntilQuit", detail: "\(on) of \(families.count) families on")
            return
        }
        if only == "fonts-folder" {
            await checkFontsFolder(model: model)
            return
        }
        if only == "warm-launch" {
            await checkWarmLaunch(model: model)
            return
        }
        if only == "undo" {
            await checkUndo(model: model)
            return
        }
        if only == "screens" {
            let environment = ProcessInfo.processInfo.environment
            if let mode = environment["CICERO_MEASURE_MODE"].flatMap(BrowserMode.init(rawValue:)) {
                defaults.set(mode.rawValue, forKey: "browser.mode")
            }
            if let query = environment["CICERO_MEASURE_SEARCH"], !query.isEmpty {
                model.searchText = query
                _ = await until(seconds: 3, { model.appliedSearch == query })
            }
            _ = await MainSettle.wait(quiet: .milliseconds(500))
            Measurements.count("screen", detail: "browser")
            Measurements.flush()
            try? await Task.sleep(for: .seconds(3))
            if let family = model.visibleFamilies.first { model.openFamilyID = family.id }
            _ = await MainSettle.wait()
            Measurements.count("screen", detail: "page")
            Measurements.flush()
            try? await Task.sleep(for: .seconds(3))
            model.openFamilyID = nil
            return
        }
        if only == "scroll" {
            for _ in 0..<2 {
                for mode in [BrowserMode.grid, .list, .specimens] {
                    await step("mode", detail: mode.rawValue) { defaults.set(mode.rawValue, forKey: "browser.mode") }
                    await scroll(mode: mode)
                }
            }
            return
        }
        if only == "mode" || only == "mode-scrolled" {
            for _ in 0..<(only == "mode" ? 10 : 5) {
                for mode in [BrowserMode.list, .specimens, .grid] {
                    await step("mode", detail: mode.rawValue) { defaults.set(mode.rawValue, forKey: "browser.mode") }
                    if only == "mode-scrolled" { await scroll(mode: mode) }
                }
            }
            return
        }
        if only == "page" {
            let mode = ProcessInfo.processInfo.environment["CICERO_MEASURE_MODE"].flatMap(BrowserMode.init(rawValue:)) ?? .specimens
            await step("mode", detail: mode.rawValue) { defaults.set(mode.rawValue, forKey: "browser.mode") }
            _ = await MainSettle.wait(quiet: .seconds(1), limit: .seconds(10))
            let picks = pagePicks(model)
            for _ in 0..<10 {
                for family in picks {
                    await step("page.open", detail: family.name) { model.openFamilyID = family.id }
                    await step("page.close") { model.openFamilyID = nil }
                }
            }
            return
        }

        if only == "panels" {
            await step("mode", detail: "grid") { defaults.set(BrowserMode.grid.rawValue, forKey: "browser.mode") }
            _ = await MainSettle.wait(quiet: .seconds(1), limit: .seconds(10))
            let location = model.data.folders.first?.id
            let families = model.library.families.filter { location == nil || $0.folderIDs.contains(location!) }
            guard let family = families.max(by: { $0.faces.count < $1.faces.count }) else {
                return Measurements.count("run.failed", detail: "no family")
            }
            for place in ["browser", "page"] {
                if place == "page" {
                    await step("page.open", detail: family.name) { model.openFamilyID = family.id }
                    _ = await MainSettle.wait(quiet: .seconds(1), limit: .seconds(20))
                }
                for _ in 0..<10 {
                    await step("info.open.\(place)", detail: family.name) { model.isInfoPresented = true }
                    await step("info.close.\(place)", detail: family.name) { model.isInfoPresented = false }
                }
                for _ in 0..<10 {
                    await step("sidebar.hide.\(place)", detail: family.name) { toggleSidebar() }
                    await step("sidebar.show.\(place)", detail: family.name) { toggleSidebar() }
                }
            }
            model.openFamilyID = nil
            return
        }

        let location = model.data.folders.first.map { SidebarItem.folder($0.id) }
        let items: [SidebarItem] = [.active, .inactive, .system] + (location.map { [$0] } ?? []) + [.all]
        for _ in 0..<2 {
            for item in items {
                await step("sidebar", detail: "\(item)") { model.selection = item }
            }
        }

        var applied: MainSettle?
        model.searchApplies = { applied = MainSettle.begin() }
        for query in ["ga", "sans", "bold", "mono", "hel", "variable", "perf 1", "zz"] {
            applied = nil
            model.searchText = query
            guard await until(seconds: 2, { applied != nil && model.appliedSearch == query }), let settle = applied else { continue }
            let settled = await settle.wait()
            Measurements.record("search", ms: settled.ms, detail: "\(query): \(model.visibleFamilies.count)")
            Measurements.record("search.work", ms: settled.workMs)
            Measurements.record("search.longest", ms: settled.longestMs)
            await step("search.clear") { model.searchText = "" }
        }
        model.searchApplies = nil

        let picks = pagePicks(model)
        for family in picks {
            await step("page.open", detail: family.name) { model.openFamilyID = family.id }
            await step("page.close") { model.openFamilyID = nil }
        }

        for family in picks {
            await step("rate", detail: family.name) { model.setRating(3, for: [family]) }
            await step("rate.clear") { model.setRating(nil, for: [family]) }
        }

        for _ in 0..<3 {
            let ended = model.endedScans
            let start = ContinuousClock.now
            NotificationCenter.default.post(name: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil)
            guard await until(seconds: 60, { model.endedScans > ended }) else { break }
            Measurements.record("fontsChanged", ms: (ContinuousClock.now - start).milliseconds)
            _ = await MainSettle.wait()
        }

        for end in "Hamburgefonstiv".indices.dropFirst() {
            await step("defaults.write") { defaults.set(String("Hamburgefonstiv"[..<end]), forKey: "measure.scratch") }
        }
        defaults.removeObject(forKey: "measure.scratch")

        let text = "Sphinx of black quartz"
        for mode in [BrowserMode.grid, .list, .specimens] {
            await step("mode", detail: mode.rawValue) { defaults.set(mode.rawValue, forKey: "browser.mode") }
            for family in picks.prefix(3) {
                await step("rate.\(mode.rawValue)", detail: family.name) { model.setRating(4, for: [family]) }
                await step("rate.\(mode.rawValue)", detail: family.name) { model.setRating(nil, for: [family]) }
            }
            for end in text.indices.dropFirst() where text[text.index(before: end)] != " " {
                await step("type.\(mode.rawValue)") { preview.sampleText = String(text[..<end]) }
            }
            await step("type.clear") { preview.sampleText = "" }
            await scroll(mode: mode)
        }
        defaults.set(BrowserMode.grid.rawValue, forKey: "browser.mode")
        _ = await MainSettle.wait()
    }

    // MARK: Warm launch

    private static func checkWarmLaunch(model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["CICERO_MEASURE_PHASE"] ?? "1"
        let widths = SampleWidths.shared
        _ = await until(seconds: 60) { !widths.measuredLog.isEmpty }
        _ = await MainSettle.wait(quiet: .seconds(2), limit: .seconds(60))
        let log = widths.measuredLog
        Measurements.count("widths", detail: log.map { "\($0.new)/\($0.all)" }.joined(separator: " "))

        func notice() async -> String {
            let ended = model.endedScans
            NotificationCenter.default.post(name: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil)
            _ = await until(seconds: 60) { model.endedScans > ended }
            _ = await MainSettle.wait(quiet: .milliseconds(500))
            return LibraryScanner.lastScanDetail.withLock { $0 }
        }
        func replayed(_ detail: String) -> (Int, Int)? {
            let words = detail.split(separator: " ")
            guard detail.hasPrefix("fontd,"), words.count >= 4, let done = Int(words[1]), let all = Int(words[3]) else { return nil }
            return (done, all)
        }
        func names() -> Set<String> { Set(model.library.families.map(\.name)) }
        func has(_ path: String) -> Bool { model.library.families.contains { $0.faces.contains { $0.face.path == path } } }

        switch phase {
        case "1":
            check(log.contains { $0.new > 0 }, "a first launch measures the samples (\(log.map(\.new)))")
            try? await Task.sleep(for: .seconds(4))
            check(FileManager.default.fileExists(atPath: SampleWidths.savedURL.path), "the widths are saved")
        case "2":
            check(!log.isEmpty && log.allSatisfy { $0.new == 0 }, "a warm launch measures no sample (\(log.map(\.new)))")
            let listed = model.library.families.filter(model.data.lists).count
            check(log.last.map { $0.all == listed } ?? false, "it knows every family's sample (\(log.last?.all ?? 0) of \(listed))")

            let before = names()
            let first = await notice()
            let counts = replayed(first)
            check(counts.map { $0.0 == $0.1 && $0.1 > 0 } ?? false, "a notice replays every watched folder (\(first))")
            check(names() == before, "the families are the same after it (\(before.count) → \(names().count))")

            guard let folder = model.data.folders.first?.path, let extra = environment["CICERO_MEASURE_EXTRA"] else {
                return check(false, "a location and a file to add")
            }
            // Into the location's own folder: a new folder would make FSEvents say only that something changed in it, which walks every folder again.
            let added = folder + "/" + (extra as NSString).lastPathComponent
            var measured = widths.measuredLog.count
            try? FileManager.default.copyItem(atPath: extra, toPath: added)
            check(await until(seconds: 20) { has(added) }, "a file added to the location shows")
            _ = await until(seconds: 20) { widths.measuredLog.count > measured }
            _ = await MainSettle.wait(quiet: .seconds(1))
            check(widths.measuredLog.last?.new == 1, "only its sample is measured (\(widths.measuredLog.last.map(\.new) ?? -1))")

            let second = await notice()
            let after = replayed(second)
            check(after.map { $0.0 == $0.1 - 1 } ?? false, "the next notice walks its folder again, replays the rest (\(second))")
            check(has(added), "the added file stays after it")

            measured = widths.measuredLog.count
            guard let existing = model.library.families.first(where: { family in
                family.folderIDs.contains(model.data.folders[0].id) && !family.faces.contains { $0.face.path == added }
            })?.faces.first?.face.path else { return check(false, "a family of the location") }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: existing)
            _ = await until(seconds: 20) { widths.measuredLog.count > measured }
            _ = await MainSettle.wait(quiet: .seconds(1))
            check(widths.measuredLog.last?.new == 1, "a file saved again is measured again (\(widths.measuredLog.last.map(\.new) ?? -1))")
            let afterSave = await notice()
            check(replayed(afterSave).map { $0.0 == $0.1 - 1 } ?? false, "so is the next notice after it (\(afterSave))")

            try? FileManager.default.removeItem(atPath: added)
            check(await until(seconds: 20) { !has(added) }, "a file removed from the location goes")
            let third = await notice()
            check(!has(added), "it stays gone after the next notice (\(third))")
            check(names() == before, "the families are those before (\(before.count) → \(names().count))")
        case "3":
            let detail = await notice()
            check(detail == "full", "a notice walks every folder once the last walk is older than CICERO_MEASURE_WALK_EVERY (\(detail))")
        default:
            check(false, "phase \(phase)")
        }
    }

    // MARK: Undo

    private static func check(_ passed: Bool, _ what: String) {
        Measurements.count("check", detail: "\(passed ? "PASS" : "FAIL")  \(what)")
    }

    private static func settled(_ model: AppModel) async {
        await model.enqueued { _ in }
        let ended = model.endedScans
        _ = await until(seconds: 20) { model.endedScans > ended }
        _ = await MainSettle.wait(quiet: .milliseconds(300))
    }

    private static func position(_ model: AppModel, _ id: String) -> SwitchPosition? { model.family(id)?.position }

    private static func checkUndo(model: AppModel) async {
        guard let location = model.data.folders.first?.id else { return check(false, "a location to test with") }
        let off = model.library.families.filter { $0.folderIDs.contains(location) && $0.position == .off }
        guard off.count >= 6 else { return check(false, "six families off in the location (\(off.count))") }
        let (one, two, three, four, five, six) = (off[0].id, off[1].id, off[2].id, off[3].id, off[4].id, off[5].id)

        model.activate([off[0]])
        await settled(model)
        check(position(model, one) == .on, "turning on \(one) turns it on")
        check(model.toastUndo != nil, "its toast has an Undo")
        model.undoToast()
        await settled(model)
        check(position(model, one) == .off, "Undo turns \(one) off again")

        model.activate([off[1]])
        await settled(model)
        if let family = model.family(two) { model.deactivate([family]) }
        await settled(model)
        check(position(model, two) == .off, "turning \(two) off turns it off")
        model.undoToast()
        await settled(model)
        check(position(model, two) == .on, "Undo turns \(two) on again")

        model.activate([off[2]])
        await settled(model)
        var data = model.data
        if !data.tags.contains("Client") { data.tags.append("Client") }
        data.familyTags[three] = ["Client"]
        data.familyRatings[three] = 4
        data.familyNotes[three] = "For the client"
        let folder = FontSet(name: "Project", families: [three, four])
        data.sets.append(folder)
        model.data = data
        let families = [three, four, five, six].compactMap(model.family)
        let paths = { (id: String) in model.family(id).map { $0.faces.map(\.face.path) } ?? [] }
        let (threePaths, fourPaths, fivePaths, sixPaths) = (paths(three), paths(four), paths(five), paths(six))
        guard let plan = model.engine.trashPlan(for: families.flatMap(\.faces), removing: families.map(\.id), in: model.library, title: "Test") else {
            return check(false, "a plan to move the families to the Trash")
        }
        model.moveToTrash(plan)
        await settled(model)
        let fm = FileManager.default
        check((threePaths + fourPaths).allSatisfy { !fm.fileExists(atPath: $0) }, "Move to Trash takes the files away")
        check(model.data.familyRatings[three] == nil && model.data.familyNotes[three] == nil, "and forgets the rating and the note")
        guard let undo = model.toastUndo else { return check(false, "Move to Trash's toast has an Undo") }
        check(true, "Move to Trash's toast has an Undo")

        // Listing the Trash takes Full Disk Access, which a test copy hasn't.
        let trashed = fivePaths.compactMap { model.lastTrashed[$0] }
        for path in trashed { try? fm.removeItem(atPath: path) }
        check(!trashed.isEmpty && trashed.allSatisfy { !fm.fileExists(atPath: $0) }, "five's files taken out of the Trash (\(trashed.count))")
        let standIn = sixPaths.first ?? ""
        fm.createFile(atPath: standIn, contents: Data("stand-in".utf8))
        let fourFolder = (fourPaths.first.map { ($0 as NSString).deletingLastPathComponent }) ?? ""
        try? fm.removeItem(atPath: fourFolder)
        check(!fm.fileExists(atPath: fourFolder), "four's folder taken away")

        undo()
        await settled(model)
        check((threePaths + fourPaths).allSatisfy { fm.fileExists(atPath: $0) }, "Undo puts three's and four's files back, four's folder made again")
        check(position(model, three) == .on, "three is on again")
        check(position(model, four) == .off, "four is off, as it was")
        check(model.data.familyTags[three] == ["Client"] && model.data.familyRatings[three] == 4
              && model.data.familyNotes[three] == "For the client", "three's tag, rating and note are back")
        let project = model.data.sets.first { $0.id == folder.id }
        check(project?.families.contains(three) == true && project?.families.contains(four) == true, "three and four are in the folder again")
        check(fivePaths.allSatisfy { !fm.fileExists(atPath: $0) }, "five, no longer in the Trash, stays away")
        check((try? String(contentsOfFile: standIn, encoding: .utf8)) == "stand-in", "the file where six was is left as it is")
        let message = model.toast ?? ""
        check(message.contains("no longer in the Trash") && message.contains("where another file is now"), "the toast says what didn't go back: \(message)")
    }

    private static func checkFontsFolder(model: AppModel) async {
        let names = (ProcessInfo.processInfo.environment["CICERO_MEASURE_FAMILIES"] ?? "").split(separator: ",").map(String.init)
        let fonts = model.locations.userFonts.path + "/"
        _ = await until(seconds: 30) { names.allSatisfy { model.family($0)?.position == .on } }
        let families = names.compactMap(model.family)
        guard families.count == 3 else { return check(false, "the three families in the Fonts folder (\(families.count))") }
        let (a, b, c) = (names[0], names[1], names[2])
        check(families.allSatisfy { $0.faces.allSatisfy { $0.face.path.hasPrefix(fonts) } && $0.position == .on },
              "the three families are in ~/Library/Fonts, on")
        let paths = { (id: String) in model.family(id).map { $0.faces.map(\.face.path) } ?? [] }

        if let family = model.family(b) { model.deactivate([family]) }
        await settled(model)
        check(position(model, b) == .off && paths(b).allSatisfy { FileManager.default.fileExists(atPath: $0) },
              "turning \(b) off in the Fonts folder leaves its files there, off")
        model.undoToast()
        await settled(model)
        check(position(model, b) == .on, "Undo turns \(b) on again")

        if let family = model.family(b) { model.deactivate([family]) }
        await settled(model)
        check(position(model, b) == .off, "\(b) off again before the Trash")
        let (aPaths, bPaths) = (paths(a), paths(b))
        let pair = [a, b].compactMap(model.family)
        guard let plan = model.engine.trashPlan(for: pair.flatMap(\.faces), removing: pair.map(\.id), in: model.library, title: "Test") else {
            return check(false, "a plan to move \(a) and \(b) to the Trash")
        }
        model.moveToTrash(plan)
        await settled(model)
        check((aPaths + bPaths).allSatisfy { !FileManager.default.fileExists(atPath: $0) }, "Move to Trash takes their files out of the Fonts folder")
        guard let undo = model.toastUndo else { return check(false, "Move to Trash's toast has an Undo") }
        undo()
        await settled(model)
        // macOS turns a file that comes back to the Fonts folder on by itself: give it the time it takes, then look again.
        _ = await until(seconds: 15) { position(model, b) == .off && position(model, a) == .on }
        check((aPaths + bPaths).allSatisfy { FileManager.default.fileExists(atPath: $0) }, "Undo puts their files back in the Fonts folder")
        check(position(model, a) == .on, "\(a), on before, is on")
        check(position(model, b) == .off, "\(b), off before, is off again, though macOS turned it on as it came back")

        let again = [a, b].compactMap(model.family)
        guard let plan2 = model.engine.trashPlan(for: again.flatMap(\.faces), removing: again.map(\.id), in: model.library, title: "Test") else {
            return check(false, "a plan to move \(a) and \(b) to the Trash again")
        }
        model.moveToTrash(plan2)
        await settled(model)
        let bTrash = bPaths.compactMap { model.lastTrashed[$0] }
        check(bTrash.count == bPaths.count, "\(b)'s places in the Trash recorded (\(bTrash.count) of \(bPaths.count))")
        for path in bTrash { try? Data(repeating: 0x2A, count: 4096).write(to: URL(fileURLWithPath: path)) }
        guard let undo2 = model.toastUndo else { return check(false, "the second Move to Trash's toast has an Undo") }
        let started = ContinuousClock.now
        undo2()
        await settled(model)
        _ = await until(seconds: 15) { position(model, a) == .on }
        let took = (ContinuousClock.now - started).milliseconds
        check(bPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) }, "\(b), which macOS won't take, isn't in the Fonts folder")
        check(!bTrash.isEmpty && bTrash.allSatisfy { FileManager.default.fileExists(atPath: $0) }, "\(b)'s file is still in the Trash, where it was")
        check(aPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) } && position(model, a) == .on, "\(a) is back, on")
        check(!FileManager.default.fileExists(atPath: model.locations.support.appendingPathComponent("turning-off.json").path), "no list of files turning off left behind")
        let message = model.toast ?? ""
        check(message == "Put back 1 of 2 files: 1 couldn\u{2019}t be moved", "the toast: \(message)")
        check(took < 15_000, "Undo took \(Int(took)) ms")
        Measurements.count("refusedInTrash", detail: bTrash.joined(separator: "|"))

        if let family = model.family(c) { model.deactivate([family]) }
        await settled(model)
        if let family = model.family(c) { model.activateTemporarily(family.faces, confirmed: true) }
        await settled(model)
        check(position(model, c) == .on && model.family(c)?.faces.allSatisfy(\.isOnUntilQuit) == true, "\(c) on until Cicero quits")
        Measurements.count("quitting", detail: paths(c).joined(separator: "|"))
    }

    private static func scroll(mode: BrowserMode) async {
        guard let scrollView = browserScrollView() else { return Measurements.count("scroll.unavailable", detail: mode.rawValue) }
        let clip = scrollView.contentView
        let pages = Int(ProcessInfo.processInfo.environment["CICERO_MEASURE_PAGES"] ?? "") ?? 15
        for page in 1...max(1, pages) {
            let height = clip.bounds.height
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - height)
            let y = min(maxY, clip.bounds.origin.y + height)
            if y <= clip.bounds.origin.y { break }
            await step("scroll.\(mode.rawValue)", detail: "page \(page)") {
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
                scrollView.reflectScrolledClipView(clip)
            }
        }
        await step("scroll.top", detail: mode.rawValue) {
            clip.scroll(to: .zero)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    private static func browserScrollView() -> NSScrollView? {
        guard let content = TextEditingKeys.mainWindow?.contentView else { return nil }
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, !(scroll.documentView is NSTableView) { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(content)
        return found.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func pagePicks(_ model: AppModel) -> [Family] {
        let families = model.visibleFamilies
        return families.isEmpty ? [] : (0..<5).map { families[$0 * (families.count - 1) / 4] }
    }

    private static func toggleSidebar() {
        func controller(in view: NSView) -> NSSplitViewController? {
            if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.contains(where: { $0.behavior == .sidebar }) { return controller }
            for child in view.subviews { if let found = controller(in: child) { return found } }
            return nil
        }
        guard let view = TextEditingKeys.mainWindow?.contentView, let split = controller(in: view) else {
            return Measurements.count("run.failed", detail: "no sidebar")
        }
        split.toggleSidebar(nil)
    }

    private static func step(_ name: String, detail: String = "", _ change: () -> Void) async {
        let signpost = Measurements.signposter.beginInterval("Step", "\(name, privacy: .public) \(detail, privacy: .public)")
        let settle = MainSettle.begin()
        change()
        let settled = await settle.wait()
        Measurements.signposter.endInterval("Step", signpost)
        Measurements.record(name, ms: settled.ms, detail: settled.timedOut ? "\(detail) (limit)" : detail)
        Measurements.record("\(name).work", ms: settled.workMs, detail: detail)
        Measurements.record("\(name).longest", ms: settled.longestMs, detail: detail)
        Measurements.record("\(name).slow", ms: Double(settled.slowTurns), detail: detail)
    }

    private static func launchStep(_ name: String, detail: String = "") async {
        let settled = await MainSettle.wait()
        let end = Measurements.sinceProcessStart - (ContinuousClock.now - settled.end).milliseconds
        Measurements.record(name, ms: end, detail: detail)
    }

    private static func until(seconds: Double = 0, minutes: Double = 0, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds + minutes * 60)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}

final class MainSettle {
    struct Result {
        var ms: Double
        var end: ContinuousClock.Instant
        var timedOut: Bool
        var workMs: Double
        var longestMs: Double
        var slowTurns: Int
    }

    private let start: ContinuousClock.Instant
    private var wake: ContinuousClock.Instant?
    private var lastBusyEnd: ContinuousClock.Instant
    private var sawTurn = false
    private var work: Duration = .zero
    private var longest: Duration = .zero
    private var slowTurns = 0
    private var observer: CFRunLoopObserver?

    private init() {
        start = .now
        lastBusyEnd = start
    }

    static func begin() -> MainSettle {
        let settle = MainSettle()
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        // After every other observer, Core Animation's commit (order 2,000,000) among them.
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, CFIndex.max) { [weak settle] _, activity in
            MainActor.assumeIsolated { settle?.observe(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        settle.observer = observer
        return settle
    }

    static func wait(quiet: Duration = .milliseconds(100), limit: Duration = .seconds(5)) async -> Result {
        await begin().wait(quiet: quiet, limit: limit)
    }

    private func observe(_ activity: CFRunLoopActivity) {
        let now = ContinuousClock.now
        if activity == .afterWaiting {
            wake = now
        } else {
            let turn = now - (wake ?? start)
            if wake == nil || turn > .milliseconds(1) {
                lastBusyEnd = now
                work += turn
                longest = max(longest, turn)
                if turn > .microseconds(16_700) { slowTurns += 1 }
            }
            wake = nil
            sawTurn = true
        }
    }

    func wait(quiet: Duration = .milliseconds(100), limit: Duration = .seconds(5)) async -> Result {
        defer {
            if let observer { CFRunLoopObserverInvalidate(observer) }
            observer = nil
        }
        var timedOut = false
        while true {
            try? await Task.sleep(for: .milliseconds(10))
            let now = ContinuousClock.now
            if sawTurn, now - lastBusyEnd >= quiet { break }
            if now - start >= limit {
                timedOut = true
                break
            }
        }
        return Result(ms: (lastBusyEnd - start).milliseconds, end: lastBusyEnd, timedOut: timedOut,
                      workMs: work.milliseconds, longestMs: longest.milliseconds, slowTurns: slowTurns)
    }
}
#endif
