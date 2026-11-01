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
        // screens: the grid, then the first family's page, 3 s each, a "screen" line as each shows, for screenshots
        // (Tests/E2E/app-perf/screens.sh).
        if only == "screens" {
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
