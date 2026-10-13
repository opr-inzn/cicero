import os

/// Intervals for Instruments' os_signpost instrument (subsystem com.maximilianinzinger.Cicero), so activation,
/// scans and coverage can be timed rather than judged by feel. They cost nothing while nothing records.
public enum Signposts {
    public static let activation = OSSignposter(subsystem: subsystem, category: "Activation")
    public static let library = OSSignposter(subsystem: subsystem, category: "Library")

    private static let subsystem = "com.maximilianinzinger.Cicero"
}
