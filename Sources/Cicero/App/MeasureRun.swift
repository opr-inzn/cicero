// Only in the app performance runs' builds (`-D CICERO_MEASURE`, see Sources/CiceroCore/Measurements.swift).
#if CICERO_MEASURE
import AppKit
import CiceroCore
import CoreText

/// The app performance runs' scenario (Tests/E2E/app-perf): with `CICERO_MEASURE=<file>` and `CICERO_MEASURE_RUN=1`,
/// Cicero times its launch, then types, searches, picks sidebar items, opens font pages, scrolls and rates by itself,
/// each step timed until the main thread is quiet again (`MainSettle`), writes every timing to the file and quits.
/// It drives the model as the views' bindings do, not with key presses. It never turns a font on or off.
enum MeasureRun {
    private static var task: Task<Void, Never>?

    static var isAsked: Bool {
        ProcessInfo.processInfo.environment["CICERO_MEASURE_RUN"] == "1" && Measurements.isRecording
    }

    /// Called as the main window appears. With `CICERO_MEASURE` alone, as in the VM end-to-end runs, it only watches the
    /// main thread for stalls (and the app records list rebuilds and main-thread reads); with `CICERO_MEASURE_RUN=1`
    /// too, it runs the scenario. Without either, nothing.
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
        // Launch: each as the time since the process started, until the main thread was quiet after it.
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

        // CICERO_MEASURE_ONLY=mode: only switching views, 10 rounds; mode-scrolled: each after scrolling 15 pages down
        // and back, 5 rounds. For profiling one thing (Tests/E2E/app-perf/profile.sh).
        let only = ProcessInfo.processInfo.environment["CICERO_MEASURE_ONLY"]
        // activate-kill, in a VM only (Tests/E2E/app-perf/guest-kill.sh): turns three families of the first location on,
        // waits for the operation to end, and kills Cicero at once, so what it saved by then is what the user data has.
        // The one scenario that turns fonts on.
        if only == "activate-kill" {
            guard let location = model.data.folders.first?.id else { return Measurements.count("run.failed", detail: "no location") }
            let families = Array(model.library.families.filter { $0.folderIDs.contains(location) && $0.position == .off }.prefix(3))
            model.activate(families)
            await model.enqueued { _ in }
            Measurements.count("activated", detail: families.map(\.name).joined(separator: ", "))
            Measurements.flush()
            kill(getpid(), SIGKILL)
        }
        // quit-temp, in a VM only (Tests/E2E/app-perf/guest-quit.sh): turns CICERO_MEASURE_COUNT families of the first
        // location on until Cicero quits, then quits, which times turning them off again (quit.endUntilQuit).
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
        // fonts-folder, in a VM's own account only (Tests/E2E/app-perf/guest-fonts-folder.sh), with the families
        // CICERO_MEASURE_FAMILIES names in its ~/Library/Fonts: turning off there and Undo, Move to Trash and Undo, and
        // the third on until Cicero quits, which the script checks is off once Cicero has gone.
        if only == "fonts-folder" {
            await checkFontsFolder(model: model)
            return
        }
        // warm-launch (Tests/E2E/warm-launch/run.sh): saved sample widths and the scans after a fonts-changed notice.
        if only == "warm-launch" {
            await checkWarmLaunch(model: model)
            return
        }
        // undo, in a VM only (Tests/E2E/app-perf/guest-undo.sh): Undo after turning fonts on and off, and after Move to
        // Trash, with the ways putting back can fail; a "check" line, PASS or FAIL, for each thing checked.
        if only == "undo" {
            await checkUndo(model: model)
            return
        }
        // screens: the grid, then the first family's page, 3 s each, a "screen" line as each shows, for screenshots
        // (Tests/E2E/app-perf/screens.sh).
        if only == "screens" {
            // CICERO_MEASURE_MODE: the view to show (list, grid or specimens); CICERO_MEASURE_SEARCH: a search first.
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
        // scroll: 15 pages down and back in each view, twice.
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

        // Sidebar items, each twice.
        let location = model.data.folders.first.map { SidebarItem.folder($0.id) }
        let items: [SidebarItem] = [.active, .inactive, .system] + (location.map { [$0] } ?? []) + [.all]
        for _ in 0..<2 {
            for item in items {
                await step("sidebar", detail: "\(item)") { model.selection = item }
            }
        }

        // Search, from the applied search (after its pause).
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

        // Font pages: five families across the list.
        let families = model.visibleFamilies
        let picks = families.isEmpty ? [] : (0..<5).map { families[$0 * (families.count - 1) / 4] }
        for family in picks {
            await step("page.open", detail: family.name) { model.openFamilyID = family.id }
            await step("page.close") { model.openFamilyID = nil }
        }

        // Ratings: each change of user data makes the lists again.
        for family in picks {
            await step("rate", detail: family.name) { model.setRating(3, for: [family]) }
            await step("rate.clear") { model.setRating(nil, for: [family]) }
        }

        // CoreText's fonts-changed notification, as another app (Font Book, Creative Cloud) turning fonts on or off sends
        // it: Cicero scans everything again. Nothing changed, so the scan applies nothing; timed until it ends.
        for _ in 0..<3 {
            let ended = model.endedScans
            let start = ContinuousClock.now
            NotificationCenter.default.post(name: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String), object: nil)
            guard await until(seconds: 60, { model.endedScans > ended }) else { break }
            Measurements.record("fontsChanged", ms: (ContinuousClock.now - start).milliseconds)
            _ = await MainSettle.wait()
        }

        // What one letter saved to the defaults costs the main window, as Compare and the Character Toolbox saved their
        // text with each letter: SwiftUI draws every view with an @AppStorage again, whatever the key.
        for end in "Hamburgefonstiv".indices.dropFirst() {
            await step("defaults.write") { defaults.set(String("Hamburgefonstiv"[..<end]), forKey: "measure.scratch") }
        }
        defaults.removeObject(forKey: "measure.scratch")

        // In each view: switch to it, type into Preview Options' text one letter at a time, scroll down.
        let text = "Sphinx of black quartz"
        for mode in [BrowserMode.grid, .list, .specimens] {
            await step("mode", detail: mode.rawValue) { defaults.set(mode.rawValue, forKey: "browser.mode") }
            // A rating while this view shows: the list makes its rows again for each change of user data.
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

    /// CICERO_MEASURE_PHASE 1, a first launch: the grid's sample widths are measured and saved. 2, the next launch: none
    /// is measured; a fonts-changed notice replays every watched folder's walk; a font file added to the first location,
    /// changed or removed shows, is measured alone, and its folder is walked again at the next notice. 3, with
    /// CICERO_MEASURE_WALK_EVERY=0: a notice walks every folder. CICERO_MEASURE_EXTRA: a font file to add.
    private static func checkWarmLaunch(model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["CICERO_MEASURE_PHASE"] ?? "1"
        let widths = SampleWidths.shared
        // The grid measures the samples of the library restored at launch, then of the first scan's.
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
        /// "fontd, 3 of 4 folders replayed" → (3, 4).
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
            // Into the location's own folder: a new folder would make FSEvents say only that something changed in it,
            // which walks every folder again.
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

            // A file saved again: its sample is measured again.
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

    /// Waits for the queued operations, then for the scans they started to end and the window to be quiet.
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

        // A. Turning on and off.
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

        // B. Move to Trash: three on, with a tag, a rating, a note and a folder; four off, in the folder too.
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

        // The ways putting back can fail: five's file gone from the Trash, another file where six's was, four's folder gone.
        // By the places Move to Trash recorded: listing the Trash takes Full Disk Access, which a test copy hasn't.
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

        // Turning off in the Fonts folder, where the file stays, and Undo.
        if let family = model.family(b) { model.deactivate([family]) }
        await settled(model)
        check(position(model, b) == .off && paths(b).allSatisfy { FileManager.default.fileExists(atPath: $0) },
              "turning \(b) off in the Fonts folder leaves its files there, off")
        model.undoToast()
        await settled(model)
        check(position(model, b) == .on, "Undo turns \(b) on again")

        // Move to Trash with one on and one off in the Fonts folder, and Undo.
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

        // Again, with b's file in the Trash made into one macOS won't take: it must stay in the Trash, off, and the toast
        // say so; a still comes back on.
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

        // On until Cicero quits, from off in the Fonts folder; the script looks once Cicero has gone.
        if let family = model.family(c) { model.deactivate([family]) }
        await settled(model)
        if let family = model.family(c) { model.activateTemporarily(family.faces, confirmed: true) }
        await settled(model)
        check(position(model, c) == .on && model.family(c)?.faces.allSatisfy(\.isOnUntilQuit) == true, "\(c) on until Cicero quits")
        Measurements.count("quitting", detail: paths(c).joined(separator: "|"))
    }

    /// Scrolls the browser down a page at a time, 15 pages unless CICERO_MEASURE_PAGES says, then back to the top.
    private static func scroll(mode: BrowserMode) async {
        guard let scrollView = browserScrollView() else { return Measurements.count("scroll.unavailable", detail: mode.rawValue) }
        let clip = scrollView.contentView
        // CICERO_MEASURE_PAGES: how many pages, 15 unless it says.
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

    /// The main window's biggest scroll view that isn't the sidebar's outline: the browser's grid, list or specimens.
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

    /// Does `change`, then records how long the main thread took to be quiet again.
    private static func step(_ name: String, detail: String = "", _ change: () -> Void) async {
        // A signpost per step, so a profile's samples can be matched to it (`Step`, its name and detail in the message).
        let signpost = Measurements.signposter.beginInterval("Step", "\(name, privacy: .public) \(detail, privacy: .public)")
        let settle = MainSettle.begin()
        change()
        let settled = await settle.wait()
        Measurements.signposter.endInterval("Step", signpost)
        Measurements.record(name, ms: settled.ms, detail: settled.timedOut ? "\(detail) (limit)" : detail)
        Measurements.record("\(name).work", ms: settled.workMs, detail: detail)
        Measurements.record("\(name).longest", ms: settled.longestMs, detail: detail)
    }

    /// Records the time since the process started, until the main thread is quiet.
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

/// Waits until the main thread has had no stretch of work over 1 ms for `quiet`: a run loop turn from waking to
/// waiting again, as CFRunLoop's observers see it (Core Animation's commit included, which runs before waiting).
/// Several turns, so work that comes a moment later, like a read finished in the background, counts too.
/// `begin` starts watching at once, in the turn the change is made in, so that turn's work counts.
final class MainSettle {
    struct Result {
        /// From the start to the end of the last busy turn.
        var ms: Double
        var end: ContinuousClock.Instant
        var timedOut: Bool
        /// The main thread's time in turns over 1 ms, and its longest turn: what an animation's many short turns add
        /// up to, and the most a click or a key press would have waited meanwhile.
        var workMs: Double
        var longestMs: Double
    }

    private let start: ContinuousClock.Instant
    private var wake: ContinuousClock.Instant?
    private var lastBusyEnd: ContinuousClock.Instant
    private var sawTurn = false
    private var work: Duration = .zero
    private var longest: Duration = .zero
    private var observer: CFRunLoopObserver?

    private init() {
        start = .now
        lastBusyEnd = start
    }

    /// Starts watching now; the turn this is called in counts as busy.
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
            // The turn watching began in has no wake of its own: it counts as busy, from the start.
            let turn = now - (wake ?? start)
            if wake == nil || turn > .milliseconds(1) {
                lastBusyEnd = now
                work += turn
                longest = max(longest, turn)
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
                      workMs: work.milliseconds, longestMs: longest.milliseconds)
    }
}
#endif
