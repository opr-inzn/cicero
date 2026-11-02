import CiceroCommands
import Foundation

/// Answers as text for people, from the same values `--json` prints. Nothing is cut short.
enum Text {
    static func string(_ value: JSON?) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }

    static func int(_ value: JSON?) -> Int? {
        switch value {
        case .int(let number): number
        case .double(let number): Int(number)
        default: nil
        }
    }

    static func bool(_ value: JSON?) -> Bool? {
        if case .bool(let flag) = value { return flag }
        return nil
    }

    static func array(_ value: JSON?) -> [JSON] {
        if case .array(let values) = value { return values }
        return []
    }

    static func strings(_ value: JSON?) -> [String] {
        array(value).compactMap(string)
    }

    static func number(_ value: Int) -> String { value.formatted() }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(number(count)) \(count == 1 ? one : many)"
    }

    /// An ISO 8601 date in the Mac's time zone, to the minute.
    static func date(_ value: JSON?) -> String? {
        guard let text = string(value), let date = try? Date(text, strategy: .iso8601) else { return nil }
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func number(_ value: JSON?) -> String {
        switch value {
        case .int(let number): String(number)
        case .double(let number): number == number.rounded() ? String(Int(number)) : String(number)
        default: ""
        }
    }

    /// Rows of cells in columns as wide as their widest cell, two spaces apart.
    static func table(_ rows: [[String]]) -> String {
        guard let columns = rows.map(\.count).max() else { return "" }
        let widths = (0..<columns).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    // MARK: Families

    static func onOff(_ family: JSON?) -> String {
        guard let status = string(family?["status"]) else { return "" }
        switch status {
        case "appOnly": return "on in \(string(family?["app"]) ?? "an app")"
        case "active": return "on"
        case "inactive": return "off"
        case "partial": return "partly on"
        case "system": return "macOS"
        default: return status
        }
    }

    static func families(_ answer: JSON) -> String {
        let families = array(answer["families"])
        let total = int(answer["total"]) ?? families.count
        let offset = int(answer["offset"]) ?? 0
        guard !families.isEmpty else {
            return total == 0 ? "No families found." : "No families after the first \(number(total))."
        }
        let rows = families.map { family in
            [string(family["name"]) ?? "", string(family["foundry"]) ?? "", string(family["class"]) ?? "",
             plural(int(family["styleCount"]) ?? 0, "style", "styles"), onOff(family)]
        }
        var text = table(rows)
        let last = offset + families.count
        if families.count < total {
            text += "\n\nFamilies \(number(offset + 1))–\(number(last)) of \(number(total))."
            if last < total { text += " For more: --offset \(last)." }
        } else {
            text += "\n\n" + plural(total, "family", "families") + "."
        }
        return text
    }

    // MARK: status

    static func status(_ answer: JSON) -> String {
        answer["familyCount"] != nil ? library(answer) : familyStatus(answer)
    }

    static func library(_ answer: JSON) -> String {
        var lines = [
            "\(plural(int(answer["familyCount"]) ?? 0, "family", "families")), \(plural(int(answer["styleCount"]) ?? 0, "style", "styles")); "
                + "\(number(int(answer["activeFamilyCount"]) ?? 0)) with a style on.",
        ]
        if let scan = date(answer["lastScan"]) { lines.append("Last scanned \(scan).") }
        let locations = array(answer["locations"])
        lines.append("")
        lines.append(locations.isEmpty ? "No locations." : "Locations:")
        lines += locations.map { "  \(string($0["name"]) ?? "")  \(string($0["path"]) ?? "")" }
        let problems = array(answer["problems"])
        lines.append("")
        lines.append(problems.isEmpty ? "No problems." : "Problems:")
        for problem in problems {
            lines.append("  \(string(problem["message"]) ?? "")")
            lines += strings(problem["paths"]).map { "    \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    static func familyStatus(_ answer: JSON) -> String {
        var lines = [string(answer["name"]) ?? ""]
        if string(answer["name"]) != string(answer["id"]) { lines[0] += " (\(string(answer["id"]) ?? ""))" }
        var facts: [[String]] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { facts.append([label + ":", value]) }
        }
        add("Status", onOff(answer))
        add("Foundry", string(answer["foundry"]))
        if string(answer["manufacturer"]) != string(answer["foundry"]) { add("Manufacturer", string(answer["manufacturer"])) }
        add("Class", string(answer["class"]))
        add("Tags", strings(answer["tags"]).joined(separator: ", "))
        add("Folders", array(answer["folders"]).compactMap { string($0["name"]) }.joined(separator: ", "))
        add("Rating", int(answer["rating"]).map { String(repeating: "★", count: $0) })
        add("Added", date(answer["added"]))
        add("Released", int(answer["released"]).map(String.init))
        add("Version", string(answer["version"]))
        add("Designer", string(answer["designer"]))
        add("Designer URL", string(answer["designerURL"]))
        add("Manufacturer URL", string(answer["manufacturerURL"]))
        add("Vendor ID", string(answer["vendorID"]))
        add("Embedding", string(answer["fsType"]))
        add("License", string(answer["license"]))
        add("License URL", string(answer["licenseURL"]))
        add("Copyright", string(answer["copyright"]))
        add("Note", string(answer["note"]))
        add("Coverage", coverage(answer["coverage"]))
        lines.append(table(facts))
        let styles = array(answer["styles"])
        lines.append("")
        lines.append(plural(styles.count, "style", "styles") + ":")
        lines.append(table(styles.map { style in
            var on = onOff(style)
            if let from = string(style["activeFrom"]) { on += " (\(from)" + (strings(style["apps"]).isEmpty ? "" : ": " + strings(style["apps"]).joined(separator: ", ")) + ")" }
            return ["  " + (string(style["name"]) ?? ""), string(style["postScriptName"]) ?? "", on, string(style["path"]) ?? ""]
        }))
        for style in styles where style["version"] != nil || style["fsType"] != nil || style["copyright"] != nil {
            lines.append("")
            lines.append(string(style["name"]) ?? "")
            var details: [[String]] = []
            func detail(_ label: String, _ value: String?) {
                if let value, !value.isEmpty { details.append(["  " + label + ":", value]) }
            }
            detail("PostScript name", string(style["postScriptName"]))
            detail("Weight", int(style["weight"]).map(String.init))
            detail("Width", int(style["width"]).map(String.init))
            detail("Italic", bool(style["italic"]).map { $0 ? "yes" : "no" })
            detail("Path", string(style["path"]).map { path in
                let index = int(style["indexInFile"]) ?? 0
                return index > 0 ? "\(path) (font \(index + 1) in the file)" : path
            })
            detail("Other copies", strings(style["otherCopies"]).joined(separator: "\n" + String(repeating: " ", count: 18)))
            detail("Axes", array(style["axes"]).map { axis in
                "\(string(axis["name"]) ?? "") \(number(axis["value"])) (\(number(axis["minimum"]))–\(number(axis["maximum"])))"
            }.joined(separator: ", "))
            detail("Version", string(style["version"]))
            detail("Released", int(style["released"]).map(String.init))
            detail("Designer", string(style["designer"]))
            detail("Designer URL", string(style["designerURL"]))
            detail("Manufacturer", string(style["manufacturer"]))
            detail("Manufacturer URL", string(style["manufacturerURL"]))
            detail("Vendor ID", string(style["vendorID"]))
            detail("Embedding", string(style["fsType"]))
            detail("License", string(style["license"]))
            detail("License URL", string(style["licenseURL"]))
            detail("Copyright", string(style["copyright"]))
            detail("Coverage", coverage(style["coverage"]))
            lines.append(table(details))
        }
        return lines.joined(separator: "\n")
    }

    static func coverage(_ coverage: JSON?) -> String? {
        guard let coverage else { return nil }
        var parts = [plural(int(coverage["characterCount"]) ?? 0, "character", "characters")]
        let largest = ["latin", "adobeLatin"].flatMap { strings(coverage["largest"]?[$0]) }
        if !largest.isEmpty { parts.append(largest.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }

    // MARK: coverage

    static func coverageCheck(_ answer: JSON) -> String {
        let name = "\(string(answer["family"]) ?? "") \(string(answer["style"]) ?? "")"
        let what = string(answer["set"]).map { "the set \($0)" } ?? "the text"
        if bool(answer["covered"]) == true { return "\(name) has every character of \(what)." }
        let missing = array(answer["missing"])
        return "\(name) lacks \(plural(missing.count, "character", "characters")) of \(what):\n"
            + table(missing.map { ["  " + (string($0["character"]) ?? ""), string($0["unicode"]) ?? ""] })
    }

    // MARK: list

    static func list(_ what: ListCommand.What, _ answer: JSON) -> String {
        switch what {
        case .families:
            return families(answer)
        case .tags:
            let tags = array(answer["tags"])
            if tags.isEmpty { return "No tags." }
            return table(tags.map { [string($0["name"]) ?? "", string($0["color"]) ?? "", plural(int($0["familyCount"]) ?? 0, "family", "families")] })
        case .folders:
            let folders = array(answer["folders"])
            if folders.isEmpty { return "No folders." }
            return table(folders.map { [string($0["name"]) ?? "", plural(int($0["familyCount"]) ?? 0, "family", "families"), string($0["id"]) ?? ""] })
        case .locations:
            let locations = array(answer["locations"])
            if locations.isEmpty { return "No locations." }
            return table(locations.map { [string($0["name"]) ?? "", string($0["path"]) ?? ""] })
        case .foundries:
            let foundries = array(answer["foundries"])
            if foundries.isEmpty { return "No foundries." }
            return table(foundries.map { [string($0["name"]) ?? "", plural(int($0["familyCount"]) ?? 0, "family", "families")] })
        case .coverage:
            return table(array(answer["coverage"]).map {
                [string($0["id"]) ?? "", string($0["name"]) ?? "", string($0["group"]) ?? "", plural(int($0["characterCount"]) ?? 0, "character", "characters")]
            })
        }
    }
}
