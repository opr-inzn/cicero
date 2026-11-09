import Foundation

public struct CopyTimeEstimate: Sendable {
    static let doubling = 8_000.0
    static let fontsFolderCost = 0.024
    static let fontLibraryCost = 0.0036
    static let window = 300.0
    static let paceWindow = 900.0

    public let intoFontsFolder: Bool
    private var samples: [(time: Double, done: Int)] = []
    private var start: Double?

    public init(intoFontsFolder: Bool) {
        self.intoFontsFolder = intoFontsFolder
    }

    public mutating func note(done: Int, at time: Double) {
        if let last = samples.last, done < last.done || time < last.time { samples.removeAll() }
        if samples.isEmpty { start = time }
        samples.append((time, done))
        while samples.count > 2, samples[1].time <= time - Self.paceWindow { samples.removeFirst() }
    }

    public func remaining(total: Int) -> Double? {
        guard let start, let last = samples.last, last.time - start >= Self.window, last.done < total else { return nil }
        let first = samples[0]
        let work = cost(from: first.done, to: last.done)
        guard work > 0, last.time > first.time else { return nil }
        let pace = max(1, (last.time - first.time) / (work * unitCost))
        return cost(from: last.done, to: total) * unitCost * pace
    }

    private var unitCost: Double { intoFontsFolder ? Self.fontsFolderCost : Self.fontLibraryCost }

    private func cost(from: Int, to: Int) -> Double {
        let a = Double(from), b = Double(to)
        guard intoFontsFolder else { return b - a }
        return (b - a) + (b * b - a * a) / (2 * Self.doubling)
    }

    public static func onFastMac(_ count: Int, intoFontsFolder: Bool) -> Double {
        let estimate = CopyTimeEstimate(intoFontsFolder: intoFontsFolder)
        return estimate.cost(from: 0, to: count) * (intoFontsFolder ? fontsFolderCost : fontLibraryCost)
    }

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
