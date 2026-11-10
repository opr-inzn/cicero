import Foundation

struct NameTable {
    private struct Record {
        var platform, encoding, language, nameID, offset, length: Int
    }

    private let table: Data
    private let storage: Int
    private let records: [Record]

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

    func name(_ nameID: Int) -> String?? {
        let all = records.filter { $0.nameID == nameID }
        guard let first = all.first else { return .some(nil) }
        // Only where every record is English and they all say the same: otherwise CoreText picks among them in ways that differ from one name and one font to another, or guesses encodings.
        guard all.allSatisfy(Self.isEnglish), let value = text(of: first) else { return nil }
        let trimmed = Self.trimmed(value)
        for record in all.dropFirst() {
            guard let other = text(of: record), Self.trimmed(other) == trimmed else { return nil }
        }
        return .some(trimmed)
    }

    func english(_ nameID: Int) -> String? {
        let all = records.filter { $0.nameID == nameID }
        let ranked = all.filter { $0.platform == 3 && $0.language == 0x409 } + all.filter { $0.platform == 1 && $0.language == 0 }
            + all.filter { $0.platform == 0 } + all
        return ranked.lazy.compactMap { self.text(of: $0).flatMap(Self.trimmed) }.first
    }

    private static func isEnglish(_ record: Record) -> Bool {
        record.platform == 0
            || record.platform == 1 && record.encoding == 0 && record.language == 0
            || record.platform == 3 && (record.encoding == 1 || record.encoding == 10) && record.language == 0x409
    }

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
