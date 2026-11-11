import CoreFoundation
import Foundation

enum LocalizedNames {
    static func familyNames(_ table: Data?, besides familyName: String) -> [String: String] {
        guard let table, table.count >= 6 else { return [:] }
        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= table.count else { return nil }
            return Int(table[table.startIndex + offset]) << 8 | Int(table[table.startIndex + offset + 1])
        }
        guard let format = u16(0), let count = u16(2), let storage = u16(4) else { return [:] }
        func bytes(_ offset: Int, _ length: Int) -> Data? {
            let start = storage + offset
            guard start + length <= table.count else { return nil }
            return table[(table.startIndex + start)..<(table.startIndex + start + length)]
        }
        // Format 1 names languages by tags ("ja", "zh-Hant") too, after the records.
        var tags: [String] = []
        if format == 1, let tagCount = u16(6 + count * 12) {
            for index in 0..<tagCount {
                let record = 6 + count * 12 + 2 + index * 4
                guard let length = u16(record), let offset = u16(record + 2), let data = bytes(offset, length) else { break }
                tags.append(String(data: data, encoding: .utf16BigEndian) ?? "")
            }
        }

        struct Entry {
            var nameID: Int
            var language: String
            var priority: Int
            var name: String
        }
        var entries: [Entry] = []
        for index in 0..<count {
            let record = 6 + index * 12
            guard let platform = u16(record), let encoding = u16(record + 2), let languageID = u16(record + 4),
                  let nameID = u16(record + 6), nameID == 1 || nameID == 16,
                  let length = u16(record + 8), let offset = u16(record + 10), let data = bytes(offset, length)
            else { continue }
            var language: String?
            var text: String?
            if languageID >= 0x8000 {
                let tag = languageID - 0x8000
                language = tag < tags.count ? tags[tag] : nil
            }
            switch platform {
            case 0, 3:
                if language == nil, platform == 3 {
                    language = CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode(nil, UInt32(languageID)).map { $0.rawValue as String }
                }
                text = String(data: data, encoding: .utf16BigEndian)
            case 1:  // The Mac's script encodings, which CoreFoundation numbers the same
                if language == nil {
                    language = CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes(nil, Int16(truncatingIfNeeded: languageID), -1).map { $0.rawValue as String }
                }
                let stringEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding))
                text = stringEncoding == UInt(kCFStringEncodingInvalidId) ? nil : String(data: data, encoding: String.Encoding(rawValue: stringEncoding))
            default:
                continue
            }
            guard let language, !language.isEmpty, let name = text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            // Windows' and Unicode's names before the Mac's, which are in older encodings.
            entries.append(Entry(nameID: nameID, language: language, priority: platform == 1 ? 1 : 0, name: name))
        }
        let nameID = entries.contains { $0.nameID == 16 } ? 16 : 1
        var names: [String: (priority: Int, name: String)] = [:]
        for entry in entries where entry.nameID == nameID {
            // In full, so Windows' "ja_JP" and the Mac's "ja" are one language.
            let language = Locale.Language(identifier: entry.language)
            guard language.languageCode != .english else { continue }
            let key = language.maximalIdentifier
            if let known = names[key], known.priority <= entry.priority { continue }
            names[key] = (entry.priority, entry.name)
        }
        return names.compactMapValues { $0.name == familyName ? nil : $0.name }
    }

    static let preferredLanguages = Locale.preferredLanguages

    static func name(in names: [String: String], for languages: [String] = preferredLanguages) -> String? {
        guard !names.isEmpty else { return nil }
        let candidates = names.keys.sorted().map { (language: Locale.Language(identifier: Locale.Language(identifier: $0).maximalIdentifier), name: names[$0]!) }
        for preferred in languages {
            let wanted = Locale.Language(identifier: Locale.Language(identifier: preferred).maximalIdentifier)
            if wanted.languageCode == .english { return nil }
            // The script must match too: "zh_TW" is Traditional Chinese, no name for a Mac set to Simplified.
            let matches = candidates.filter { $0.language.languageCode == wanted.languageCode && $0.language.script == wanted.script }
            if let match = matches.first(where: { $0.language.region == wanted.region }) ?? matches.first { return match.name }
        }
        return nil
    }
}
