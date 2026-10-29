import Foundation

/// How long copying an import's fonts in takes. Into ~/Library/Fonts each font costs more than the one before: macOS
/// takes longer to turn a font off the more fonts the folder has, about twice as long with 8,000 more (31,209 fonts took
/// 37 minutes in a macOS 15 VM, the first 2,000 about a minute). Into Cicero's Library each costs the same.
///
/// The speed is the last five minutes', so it follows a Mac that gets busier, and leaves behind the files at the start
/// that were in already, which go by fast. Times are seconds the Mac has been awake (`ProcessInfo.systemUptime`): a Mac
/// asleep copies nothing either.
public struct CopyTimeEstimate: Sendable {
    /// Fonts after which turning one off in the Fonts folder takes twice as long as at first.
    static let doubling = 8_000.0
    /// Seconds a font into the Fonts folder takes at first, and one into Cicero's Library, on a fast Mac: as the 31,209
    /// fonts went in the VM, in 37 minutes and 112 seconds.
    static let fontsFolderCost = 0.024
    static let fontLibraryCost = 0.0036
    /// How much copying it takes to say how much is left, and how far back the speed is taken from.
    static let window = 300.0

    public let intoFontsFolder: Bool
    private var samples: [(time: Double, done: Int)] = []
    private var start: Double?

    public init(intoFontsFolder: Bool) {
        self.intoFontsFolder = intoFontsFolder
    }

    /// `done` fonts copied by `time`.
    public mutating func note(done: Int, at time: Double) {
        if let last = samples.last, done < last.done || time < last.time { samples.removeAll() }
        if samples.isEmpty { start = time }
        samples.append((time, done))
        // Older ones only to keep the one that starts the window.
        while samples.count > 2, samples[1].time <= time - Self.window { samples.removeFirst() }
    }

    /// Seconds left to copy `total`: nil until the copying has gone on for five minutes, or when nothing was copied in
    /// the last five.
    public func remaining(total: Int) -> Double? {
        guard let start, let last = samples.last, last.time - start >= Self.window, last.done < total else { return nil }
        let first = samples[0]
        let work = cost(from: first.done, to: last.done)
        guard work > 0, last.time > first.time else { return nil }
        return (last.time - first.time) / work * cost(from: last.done, to: total)
    }

    /// The fonts from `from` to `to`, each counted as what it costs next to the first font.
    private func cost(from: Int, to: Int) -> Double {
        let a = Double(from), b = Double(to)
        guard intoFontsFolder else { return b - a }
        return (b - a) + (b * b - a * a) / (2 * Self.doubling)
    }

    /// Seconds copying `count` fonts takes on a fast Mac.
    public static func onFastMac(_ count: Int, intoFontsFolder: Bool) -> Double {
        let estimate = CopyTimeEstimate(intoFontsFolder: intoFontsFolder)
        return estimate.cost(from: 0, to: count) * (intoFontsFolder ? fontsFolderCost : fontLibraryCost)
    }

    /// "less than a minute", "3 minutes", "25 minutes", "1 hour", "1 hour 20 minutes", "2 hours": rounded up, to
    /// the minute up to 10 minutes, to 5 minutes up to an hour, then to 10 minutes.
    public static func phrase(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "less than a minute" }
        var minutes = Int((seconds / 60).rounded(.up))
        if minutes > 10 { minutes = (minutes + 4) / 5 * 5 }
        if minutes > 60 { minutes = (minutes + 9) / 10 * 10 }
        guard minutes >= 60 else { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = minutes / 60, rest = minutes % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? hourText : "\(hourText) \(rest) minutes"
    }
}
