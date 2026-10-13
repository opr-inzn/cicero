import Foundation

/// Finds font files anywhere on the Mac by a font's PostScript name, through Spotlight, which lists the names
/// inside every font file it indexes (kMDItemFonts). Spotlight's index is on this Mac; nothing leaves it.
public enum FontFileSearch {
    /// The font files Spotlight knows with this PostScript name, newest first; none in the Trash.
    @concurrent
    public static func files(withPostScriptName name: String) async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query(for: name)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { path in
            FontFileReader.fontExtensions.contains((path as NSString).pathExtension.lowercased()) && !path.contains("/.Trash/")
        }
        return paths.sorted { modified($0) > modified($1) }
    }

    /// `kMDItemFonts == "Name"`, with the quotes and backslashes in the name escaped and Spotlight's wildcards
    /// taken literally.
    static func query(for name: String) -> String {
        var escaped = ""
        for character in name {
            if character == "\"" || character == "\\" || character == "*" || character == "?" { escaped.append("\\") }
            escaped.append(character)
        }
        return "kMDItemFonts == \"\(escaped)\""
    }

    private static func modified(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
    }
}
