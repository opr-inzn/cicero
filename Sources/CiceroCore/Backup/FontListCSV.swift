import Foundation

/// The font list as a CSV file for a spreadsheet: a row per family, with what Cicero knows about it.
public enum FontListCSV {
    /// One family, as the app describes it: with the user's names for its foundry and classification, its tags,
    /// rating and note.
    public struct Row: Sendable {
        public var family: Family
        public var foundry: String?
        public var classification: String
        public var status: String
        public var tags: [String]
        public var rating: Int?
        public var note: String?

        public init(family: Family, foundry: String?, classification: String, status: String, tags: [String], rating: Int?, note: String?) {
            self.family = family
            self.foundry = foundry
            self.classification = classification
            self.status = status
            self.tags = tags
            self.rating = rating
            self.note = note
        }
    }

    static let columns = [
        "Family", "Styles", "Style Names", "Foundry", "Designer", "Version", "Year", "Format", "Classification", "Status", "Tags",
        "Rating", "Note", "Files",
    ]

    /// The file's text: a header row, then the families; lines end in CR LF, as CSV has them. A family's styles,
    /// designers, versions and tags are each one cell, its files one per line.
    public static func text(_ rows: [Row]) -> String {
        var lines = [columns.map(cell).joined(separator: ",")]
        for row in rows {
            let faces = row.family.faces.map(\.face)
            let styles: [String] = distinct(faces.map(\.styleName))
            let designers: [String] = distinct(faces.compactMap(\.designer))
            let versions: [String] = distinct(faces.compactMap { $0.version.map(FontFace.displayVersion) }.filter { !$0.isEmpty })
            let files: [String] = distinct(faces.map(\.path))
            var values: [String] = [row.family.name, String(faces.count), styles.joined(separator: ", "), row.foundry ?? ""]
            values += [designers.joined(separator: ", "), versions.joined(separator: ", "), row.family.year.map(String.init) ?? ""]
            values += [row.family.formatLabel, row.classification, row.status, row.tags.joined(separator: ", ")]
            values += [row.rating.map(String.init) ?? "", row.note ?? "", files.joined(separator: "\n")]
            lines.append(values.map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The file: UTF-8 with a byte order mark, which spreadsheets take as UTF-8, rather than reading accents as
    /// another encoding.
    public static func data(_ rows: [Row]) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text(rows).utf8)
    }

    /// A value as a cell: in quotes, its quotes doubled, when it has a comma, a quote or a line break. A value a
    /// spreadsheet would take for a formula (=, +, -, @ first) starts with an apostrophe, so it reads as text.
    static func cell(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
