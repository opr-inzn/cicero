import Foundation

/// A font's name table, read once for the names the scan keeps. CTFontCopyName goes through the whole table each time
/// it's asked, which was a fifth of reading a new file. A name is read here only where that gives what CoreText gives:
/// when the table's English records for it (Mac Roman English, Windows English, Unicode) all say the same. Where they
/// disagree, CoreText picks among them in ways that differ from one name and one font to another ("DaltonMaag Ltd."
/// from a font whose Windows record says "Dalton Maag Ltd."), and where it has others, it may guess their encodings:
/// those are left to it. Checked against CoreText for every face on a Mac, a 31,000-file FontBase library and the
/// 20,000-family test library: no difference (Tests/E2E/first-launch-memory/name-probe.swift).
struct NameTable {
    private struct Record {
        var platform, encoding, language, nameID, offset, length: Int
    }

    private let table: Data
    private let storage: Int
    private let records: [Record]

    /// nil without a table, or one too short for its own header.
    init?(_ table: Data?) {
        guard let table, table.count >= 6 else { return nil }
        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= table.count else { return nil }
            return Int(table[table.startIndex + offset]) << 8 | Int(table[table.startIndex + offset + 1])
        }
        guard let count = u16(2), let storage = u16(4) else { return nil }
        var records: [Record] = []
        records.reserveCapacity(count)
        for index in 0..<count {
            let at = 6 + index * 12
            guard let platform = u16(at), let encoding = u16(at + 2), let language = u16(at + 4), let nameID = u16(at + 6),
                  let length = u16(at + 8), let offset = u16(at + 10)
            else { return nil }
            records.append(Record(platform: platform, encoding: encoding, language: language, nameID: nameID, offset: offset, length: length))
        }
        self.table = table
        self.storage = storage
        self.records = records
    }

    /// The name with this ID, trimmed, nil when empty, as the scan keeps names: `.some(nil)` when the table has no
    /// record for it, nil when CoreText has to be asked.
    func name(_ nameID: Int) -> String?? {
        let all = records.filter { $0.nameID == nameID }
        guard let first = all.first else { return .some(nil) }
        guard all.allSatisfy(Self.isEnglish), let value = text(of: first) else { return nil }
        let trimmed = Self.trimmed(value)
        for record in all.dropFirst() {
            guard let other = text(of: record), Self.trimmed(other) == trimmed else { return nil }
        }
        return .some(trimmed)
    }

    private static func isEnglish(_ record: Record) -> Bool {
        record.platform == 0
            || record.platform == 1 && record.encoding == 0 && record.language == 0
            || record.platform == 3 && (record.encoding == 1 || record.encoding == 10) && record.language == 0x409
    }

    /// Unicode's and Windows' in UTF-16, the Mac's in Mac Roman; nil when it reaches past the table.
    private func text(of record: Record) -> String? {
        let start = storage + record.offset
        guard start + record.length <= table.count else { return nil }
        let bytes = table[(table.startIndex + start)..<(table.startIndex + start + record.length)]
        return String(data: bytes, encoding: record.platform == 1 ? .macOSRoman : .utf16BigEndian)
    }

    private static func trimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
