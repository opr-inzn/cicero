import os

public enum Signposts {
    public static let activation = OSSignposter(subsystem: subsystem, category: "Activation")
    public static let library = OSSignposter(subsystem: subsystem, category: "Library")

    private static let subsystem = "com.maximilianinzinger.Cicero"
}
