import Foundation

/// Reads an object store of a Chromium IndexedDB folder (an Electron app's `IndexedDB/file__0.indexeddb.leveldb`, with
/// big values in `file__0.indexeddb.blob` next to it), for importing another app's library. Read-only, and only what
/// the app last wrote: the LevelDB files the MANIFEST names (every one when it can't be read), newest write of each
/// key winning. The files are anyone's: every read is checked, and what can't be read is left out rather than trusted.
///
/// The layers, outside in: LevelDB (a write-ahead `.log` of write batches, and sorted `.ldb` tables, either kind maybe
/// Snappy-compressed); Chromium's keys (a prefix of database, object store and index IDs, then the encoded IndexedDB
/// key); Blink's envelope (a value too big to keep inline is in a blob file, and may be Snappy-compressed); and V8's
/// serialization of the JavaScript value itself.
public enum ChromiumIndexedDB {
    public enum Failure: Error, Equatable {
        /// No LevelDB there, or no database or object store of that name in it.
        case notFound
    }

    /// The values of the object store `store` in the database `database`, by their string keys. Keys that aren't
    /// strings and values that can't be read are left out.
    public static func values(in leveldb: URL, database: String, store: String) throws -> [String: JSValue] {
        let entries = try LevelDB.read(leveldb)
        // Database IDs by name: global metadata (prefix 0, 0, 0), type 201, the origin, then the name.
        var databaseID: Int?
        for (key, value) in entries {
            var reader = IndexedDBBytes(key)
            guard let prefix = try? KeyPrefix(&reader), prefix.database == 0, prefix.store == 0, prefix.index == 0,
                  (try? reader.byte()) == 201, (try? reader.stringWithLength()) != nil,
                  (try? reader.stringWithLength()) == database
            else { continue }
            var valueReader = IndexedDBBytes(value)
            if let id = try? valueReader.varint() { databaseID = id }
        }
        guard let databaseID else { throw Failure.notFound }
        // Object store IDs by name: the database's metadata (prefix db, 0, 0), type 200, then the name.
        var storeID: Int?
        for (key, value) in entries {
            var reader = IndexedDBBytes(key)
            guard let prefix = try? KeyPrefix(&reader), prefix.database == databaseID, prefix.store == 0, prefix.index == 0,
                  (try? reader.byte()) == 200, (try? reader.stringWithLength()) == store
            else { continue }
            var valueReader = IndexedDBBytes(value)
            if let id = try? valueReader.varint() { storeID = id }
        }
        guard let storeID else { throw Failure.notFound }

        // Records (index 1) and the blobs of those kept in blob files (index 3), by key.
        var records: [String: [UInt8]] = [:]
        var blobs: [String: [UInt8]] = [:]
        for (key, value) in entries {
            var reader = IndexedDBBytes(key)
            guard let prefix = try? KeyPrefix(&reader), prefix.database == databaseID, prefix.store == storeID,
                  prefix.index == 1 || prefix.index == 3,
                  (try? reader.byte()) == 1, let name = try? reader.stringWithLength()
            else { continue }
            if prefix.index == 1 { records[name] = value } else { blobs[name] = value }
        }
        let blobFolder = leveldb.deletingLastPathComponent()
            .appendingPathComponent(leveldb.lastPathComponent.replacingOccurrences(of: ".leveldb", with: ".blob"))
            .appendingPathComponent(String(databaseID, radix: 16))
        var values: [String: JSValue] = [:]
        for (name, record) in records {
            var reader = IndexedDBBytes(record)
            // The record's version, then the value as Blink wrote it.
            guard (try? reader.varint()) != nil else { continue }
            var bytes = Array(record[reader.offset...])
            if bytes.starts(with: [0xFF, 0x11, 0x01]) {
                // Kept in a blob file: which one is in the record's blob entry.
                var header = IndexedDBBytes(bytes)
                header.offset = 3
                guard (try? header.varint()) != nil, let index = try? header.varint(),
                      let entry = blobs[name], let number = blobNumber(entry, index: index)
                else { continue }
                let file = blobFolder.appendingPathComponent(String(format: "%02x", (number >> 8) & 0xFF))
                    .appendingPathComponent(String(number, radix: 16))
                guard let data = try? Data(contentsOf: file) else { continue }
                bytes = Array(data)
            }
            if bytes.starts(with: [0xFF, 0x11, 0x02]) {
                guard let inflated = try? Snappy.decompress(bytes[3...]) else { continue }
                bytes = inflated
            }
            if let value = try? V8Value.read(bytes) { values[name] = value }
        }
        return values
    }

    /// The number of the `index`th blob in a record's blob entry: each is whether it's a file, its number, its type,
    /// then its size, or a file's name and date.
    static func blobNumber(_ entry: [UInt8], index: Int) -> Int? {
        var reader = IndexedDBBytes(entry)
        for position in 0... {
            guard let isFile = try? reader.byte(), let number = try? reader.varint(), (try? reader.stringWithLength()) != nil else { return nil }
            if position == index { return number }
            if isFile != 0 {
                guard (try? reader.stringWithLength()) != nil, (try? reader.varint()) != nil else { return nil }
            } else {
                guard (try? reader.varint()) != nil else { return nil }
            }
            if position > 1000 { return nil }
        }
        return nil
    }

    /// The IDs a key starts with: one byte saying how many bytes each takes, then each, least significant first.
    struct KeyPrefix {
        var database: Int
        var store: Int
        var index: Int

        init(_ reader: inout IndexedDBBytes) throws {
            let sizes = Int(try reader.byte())
            database = try reader.littleEndian(((sizes >> 5) & 0x7) + 1)
            store = try reader.littleEndian(((sizes >> 2) & 0x7) + 1)
            index = try reader.littleEndian((sizes & 0x3) + 1)
        }
    }
}

/// A JavaScript value as V8 serialized it: what JSON has, and undefined.
public indirect enum JSValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSValue])
    /// Properties in the order they were written.
    case object([(key: String, value: JSValue)])

    public static func == (lhs: JSValue, rhs: JSValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)): a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public subscript(key: String) -> JSValue? {
        if case .object(let properties) = self { return properties.first { $0.key == key }?.value }
        return nil
    }

    public var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [JSValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var properties: [(key: String, value: JSValue)]? {
        if case .object(let properties) = self { return properties }
        return nil
    }
}

/// Bytes read from the front, each read checked.
struct IndexedDBBytes {
    enum Failure: Error { case truncated, malformed }

    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw Failure.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    func peek() throws -> UInt8 {
        guard offset < bytes.count else { throw Failure.truncated }
        return bytes[offset]
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count - offset else { throw Failure.truncated }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    /// LevelDB's, Chromium's and V8's unsigned varints, up to 64 bits.
    mutating func varint() throws -> Int {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let next = try byte()
            guard shift < 64 else { throw Failure.malformed }
            result |= UInt64(next & 0x7F) << shift
            if next < 0x80 { break }
            shift += 7
        }
        guard result <= UInt64(Int.max) else { throw Failure.malformed }
        return Int(result)
    }

    mutating func littleEndian(_ count: Int) throws -> Int {
        let slice = try take(count)
        var result: UInt64 = 0
        for (index, byte) in slice.enumerated() { result |= UInt64(byte) << (8 * UInt64(index)) }
        guard result <= UInt64(Int.max) else { throw Failure.malformed }
        return Int(result)
    }

    mutating func uint32() throws -> UInt32 { UInt32(try littleEndian(4)) }

    /// A Chromium string with its length: how many UTF-16 code units, then them, big-endian.
    mutating func stringWithLength() throws -> String {
        let count = try varint()
        guard count <= (bytes.count - offset) / 2 else { throw Failure.truncated }
        let slice = try take(count * 2)
        var units: [UInt16] = []
        units.reserveCapacity(count)
        var index = slice.startIndex
        while index < slice.endIndex {
            units.append(UInt16(slice[index]) << 8 | UInt16(slice[index + 1]))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: LevelDB

/// The live entries of a LevelDB folder: each key's newest value, deleted ones left out.
enum LevelDB {
    static func read(_ folder: URL) throws -> [[UInt8]: [UInt8]] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { throw ChromiumIndexedDB.Failure.notFound }
        let live = liveFiles(folder, names: names)
        var newest: [[UInt8]: (sequence: UInt64, value: [UInt8]?)] = [:]
        func keep(_ key: [UInt8], _ sequence: UInt64, _ value: [UInt8]?) {
            if let existing = newest[key], existing.sequence > sequence { return }
            newest[key] = (sequence, value)
        }
        var found = false
        for name in names.sorted() {
            guard let number = fileNumber(name) else { continue }
            let url = folder.appendingPathComponent(name)
            if name.hasSuffix(".log") {
                if let live, number < live.log { continue }
                guard let data = try? Data(contentsOf: url) else { continue }
                found = true
                readLog(Array(data), keep)
            } else if name.hasSuffix(".ldb") || name.hasSuffix(".sst") {
                if let live, !live.tables.contains(number) { continue }
                guard let data = try? Data(contentsOf: url) else { continue }
                found = true
                try? readTable(Array(data), keep)
            }
        }
        guard found else { throw ChromiumIndexedDB.Failure.notFound }
        return newest.compactMapValues(\.value)
    }

    private static func fileNumber(_ name: String) -> Int? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        return Int(name[..<dot])
    }

    /// The tables the MANIFEST that CURRENT names has, and the first log still in use; nil when it can't be read.
    static func liveFiles(_ folder: URL, names: [String]) -> (tables: Set<Int>, log: Int)? {
        guard let current = try? String(contentsOf: folder.appendingPathComponent("CURRENT"), encoding: .utf8) else { return nil }
        let manifestName = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manifestName.hasPrefix("MANIFEST-"), !manifestName.contains("/"),
              let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName))
        else { return nil }
        var tables = Set<Int>()
        var log = 0
        var previousLog = 0
        var readAny = false
        var failed = false
        readLogRecords(Array(data)) { record in
            var reader = IndexedDBBytes(record)
            do {
                while !reader.isAtEnd {
                    switch try reader.varint() {
                    case 1: _ = try reader.take(try reader.varint())  // comparator
                    case 2: log = try reader.varint()
                    case 3, 4: _ = try reader.varint()  // next file number, last sequence
                    case 5: _ = try reader.varint(); _ = try reader.take(try reader.varint())  // compact pointer
                    case 6: _ = try reader.varint(); tables.remove(try reader.varint())  // deleted file
                    case 7:  // new file: level, number, size, smallest and largest keys
                        _ = try reader.varint()
                        tables.insert(try reader.varint())
                        _ = try reader.varint()
                        _ = try reader.take(try reader.varint())
                        _ = try reader.take(try reader.varint())
                    case 9: previousLog = try reader.varint()
                    default: throw IndexedDBBytes.Failure.malformed
                    }
                }
                readAny = true
            } catch {
                failed = true
            }
        }
        guard readAny, !failed else { return nil }
        // Every table it names should be there; when one isn't, read them all rather than miss one.
        guard tables.allSatisfy({ number in names.contains { fileNumber($0) == number && ($0.hasSuffix(".ldb") || $0.hasSuffix(".sst")) } }) else {
            return nil
        }
        return (tables, previousLog > 0 ? min(log, previousLog) : log)
    }

    /// The write batches of a log: a sequence number, a count, then each put (1, key, value) or delete (0, key).
    static func readLog(_ bytes: [UInt8], _ keep: ([UInt8], UInt64, [UInt8]?) -> Void) {
        readLogRecords(bytes) { record in
            var reader = IndexedDBBytes(record)
            guard let sequence = try? reader.littleEndian(8), let count = try? reader.uint32() else { return }
            for index in 0..<Int(count) {
                guard let kind = try? reader.byte(), let keyLength = try? reader.varint(), let key = try? reader.take(keyLength) else { return }
                switch kind {
                case 1:
                    guard let valueLength = try? reader.varint(), let value = try? reader.take(valueLength) else { return }
                    keep(Array(key), UInt64(sequence) + UInt64(index), Array(value))
                case 0:
                    keep(Array(key), UInt64(sequence) + UInt64(index), nil)
                default:
                    return
                }
            }
        }
    }

    /// The records of a log file: 32 KB blocks of fragments, each with a checksum, its length and whether it's a
    /// whole record or its first, a middle or its last part. A torn or damaged fragment ends its record.
    static func readLogRecords(_ bytes: [UInt8], _ body: ([UInt8]) -> Void) {
        let blockSize = 32768
        var offset = 0
        var pending: [UInt8]?
        while offset + 7 <= bytes.count {
            let left = blockSize - offset % blockSize
            if left < 7 {
                offset += left
                continue
            }
            let checksum = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            let length = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            let kind = bytes[offset + 6]
            let start = offset + 7
            guard kind != 0, start + length <= bytes.count, length <= left - 7 else {
                // Padding, or a fragment written only in part: go on with the next block.
                offset += left
                pending = nil
                continue
            }
            offset = start + length
            guard CRC32C.masked(bytes[(start - 1)..<(start + length)]) == checksum else {
                pending = nil
                continue
            }
            let fragment = bytes[start..<(start + length)]
            switch kind {
            case 1: pending = nil; body(Array(fragment))
            case 2: pending = Array(fragment)
            case 3: pending?.append(contentsOf: fragment)
            case 4:
                if var whole = pending {
                    whole.append(contentsOf: fragment)
                    body(whole)
                }
                pending = nil
            default: pending = nil
            }
        }
    }

    /// A table: the footer gives the index block, whose entries give the data blocks. A key ends with 8 bytes of
    /// sequence number and kind (1 a value, 0 a deletion).
    static func readTable(_ bytes: [UInt8], _ keep: ([UInt8], UInt64, [UInt8]?) -> Void) throws {
        guard bytes.count >= 48 else { throw IndexedDBBytes.Failure.truncated }
        var footer = IndexedDBBytes(Array(bytes[(bytes.count - 48)...]))
        _ = try footer.varint(); _ = try footer.varint()  // metaindex
        let indexOffset = try footer.varint()
        let indexSize = try footer.varint()
        let index = try block(bytes, offset: indexOffset, size: indexSize)
        try entries(index) { _, handle in
            var reader = IndexedDBBytes(handle)
            guard let offset = try? reader.varint(), let size = try? reader.varint(),
                  let data = try? block(bytes, offset: offset, size: size)
            else { return }
            try? entries(data) { key, value in
                guard key.count >= 8 else { return }
                let tag = key.suffix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
                let userKey = Array(key.dropLast(8))
                switch tag & 0xFF {
                case 1: keep(userKey, tag >> 8, value)
                case 0: keep(userKey, tag >> 8, nil)
                default: break
                }
            }
        }
    }

    /// A block's contents, uncompressed: it's followed by its compression (0 none, 1 Snappy) and a checksum.
    private static func block(_ bytes: [UInt8], offset: Int, size: Int) throws -> [UInt8] {
        guard offset >= 0, size >= 0, offset <= bytes.count, size + 5 <= bytes.count - offset else { throw IndexedDBBytes.Failure.truncated }
        let contents = bytes[offset..<(offset + size)]
        switch bytes[offset + size] {
        case 0: return Array(contents)
        case 1: return try Snappy.decompress(contents)
        default: throw IndexedDBBytes.Failure.malformed
        }
    }

    /// A block's entries: each shares the start of the key before it. The restart points at its end aren't needed
    /// to read it from the start.
    private static func entries(_ block: [UInt8], _ body: ([UInt8], [UInt8]) throws -> Void) throws {
        guard block.count >= 4 else { throw IndexedDBBytes.Failure.truncated }
        var tail = IndexedDBBytes(Array(block.suffix(4)))
        let restarts = Int(try tail.uint32())
        guard restarts <= (block.count - 4) / 4 else { throw IndexedDBBytes.Failure.malformed }
        let end = block.count - 4 - restarts * 4
        var reader = IndexedDBBytes(Array(block[..<end]))
        var key: [UInt8] = []
        while !reader.isAtEnd {
            let shared = try reader.varint()
            let unshared = try reader.varint()
            let valueLength = try reader.varint()
            guard shared <= key.count else { throw IndexedDBBytes.Failure.malformed }
            key = Array(key[..<shared]) + (try reader.take(unshared))
            let value = Array(try reader.take(valueLength))
            try body(key, value)
        }
    }
}

/// CRC-32C, masked as LevelDB stores it.
enum CRC32C {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1 }
        return crc
    }

    static func masked(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        crc ^= 0xFFFF_FFFF
        return ((crc >> 15) | (crc << 17)) &+ 0xA282_EAD8
    }
}

/// Snappy's raw format: the uncompressed length, then literals and copies of what came before.
enum Snappy {
    static func decompress(_ input: ArraySlice<UInt8>) throws -> [UInt8] {
        var reader = IndexedDBBytes(Array(input))
        let length = try reader.varint()
        // Snappy compresses at most about 1:21; a length beyond that is a lie.
        guard length <= max(input.count, 1) * 32 else { throw IndexedDBBytes.Failure.malformed }
        var output: [UInt8] = []
        output.reserveCapacity(length)
        while !reader.isAtEnd {
            let tag = try reader.byte()
            var count: Int
            var distance: Int
            switch tag & 0x3 {
            case 0:
                count = Int(tag >> 2)
                if count >= 60 { count = try reader.littleEndian(count - 59) }
                output.append(contentsOf: try reader.take(count + 1))
                guard output.count <= length else { throw IndexedDBBytes.Failure.malformed }
                continue
            case 1:
                count = Int((tag >> 2) & 0x7) + 4
                distance = Int(tag >> 5) << 8 | Int(try reader.byte())
            case 2:
                count = Int(tag >> 2) + 1
                distance = try reader.littleEndian(2)
            default:
                count = Int(tag >> 2) + 1
                distance = try reader.littleEndian(4)
            }
            guard distance > 0, distance <= output.count, output.count + count <= length else { throw IndexedDBBytes.Failure.malformed }
            let start = output.count - distance
            for index in 0..<count { output.append(output[start + index]) }
        }
        guard output.count == length else { throw IndexedDBBytes.Failure.malformed }
        return output
    }
}

// MARK: V8

/// A value as V8's ValueSerializer wrote it, inside Blink's envelope: Blink's version (with, from 21, the offset of a
/// trailer), then V8's, then the value. Only what JSON has is read; other kinds (maps, typed arrays, regular
/// expressions…) fail, and the value is left out.
enum V8Value {
    static func read(_ bytes: [UInt8]) throws -> JSValue {
        var parser = Parser(reader: IndexedDBBytes(bytes))
        return try parser.value(depth: 0)
    }

    private struct Parser {
        var reader: IndexedDBBytes
        /// Objects by the ID a later reference gives them, in the order they were begun; nil while one is being read.
        var objects: [JSValue?] = []

        mutating func value(depth: Int) throws -> JSValue {
            guard depth < 256 else { throw IndexedDBBytes.Failure.malformed }
            while true {
                let tag = try reader.byte()
                switch tag {
                case 0xFF: _ = try reader.varint()  // a version
                case 0xFE: _ = try reader.take(12)  // Blink's trailer offset and size
                case 0x00: continue  // padding
                case UInt8(ascii: "_"), UInt8(ascii: "0"): return .null
                case UInt8(ascii: "T"): return .bool(true)
                case UInt8(ascii: "F"): return .bool(false)
                case UInt8(ascii: "I"):
                    let zigzag = try reader.varint()
                    return .number(Double((zigzag >> 1) ^ -(zigzag & 1)))
                case UInt8(ascii: "U"): return .number(Double(try reader.varint()))
                case UInt8(ascii: "N"): return .number(try double())
                case UInt8(ascii: "\""): // Latin-1: each byte is the scalar of that number.
                    return .string(String(String.UnicodeScalarView(try reader.take(try reader.varint()).map { Unicode.Scalar($0) })))
                case UInt8(ascii: "S"): return .string(String(decoding: try reader.take(try reader.varint()), as: UTF8.self))
                case UInt8(ascii: "c"):
                    let slice = try reader.take(try reader.varint())
                    guard slice.count % 2 == 0 else { throw IndexedDBBytes.Failure.malformed }
                    let units = stride(from: slice.startIndex, to: slice.endIndex, by: 2).map { UInt16(slice[$0]) | UInt16(slice[$0 + 1]) << 8 }
                    return .string(String(decoding: units, as: UTF16.self))
                case UInt8(ascii: "D"):
                    objects.append(nil)
                    let date = JSValue.number(try double())
                    objects[objects.count - 1] = date
                    return date
                case UInt8(ascii: "^"):
                    let id = try reader.varint()
                    guard id < objects.count, let object = objects[id] else { throw IndexedDBBytes.Failure.malformed }
                    return object
                case UInt8(ascii: "o"):
                    let id = begin()
                    let properties = try self.properties(until: UInt8(ascii: "{"), depth: depth)
                    _ = try reader.varint()
                    return end(id, .object(properties))
                case UInt8(ascii: "A"):
                    let id = begin()
                    let count = try reader.varint()
                    guard count <= reader.bytes.count - reader.offset else { throw IndexedDBBytes.Failure.malformed }
                    var items: [JSValue] = []
                    for _ in 0..<count {
                        // "-" is a hole.
                        if try reader.peek() == UInt8(ascii: "-") {
                            reader.offset += 1
                            items.append(.null)
                        } else {
                            items.append(try value(depth: depth + 1))
                        }
                    }
                    _ = try self.properties(until: UInt8(ascii: "$"), depth: depth)
                    _ = try reader.varint(); _ = try reader.varint()
                    return end(id, .array(items))
                case UInt8(ascii: "a"):
                    let id = begin()
                    let count = try reader.varint()
                    let properties = try self.properties(until: UInt8(ascii: "@"), depth: depth)
                    _ = try reader.varint(); _ = try reader.varint()
                    var items = [JSValue](repeating: .null, count: min(count, properties.count == 0 ? 0 : count))
                    for (key, item) in properties {
                        if let index = Int(key), index >= 0, index < items.count { items[index] = item }
                    }
                    return end(id, .array(items))
                default:
                    throw IndexedDBBytes.Failure.malformed
                }
            }
        }

        /// Key and value pairs up to `terminator`; keys that are numbers are written as text.
        private mutating func properties(until terminator: UInt8, depth: Int) throws -> [(key: String, value: JSValue)] {
            var properties: [(key: String, value: JSValue)] = []
            while true {
                while try reader.peek() == 0x00 { reader.offset += 1 }
                if try reader.peek() == terminator {
                    reader.offset += 1
                    return properties
                }
                let key: String
                switch try value(depth: depth + 1) {
                case .string(let text): key = text
                case .number(let number): key = number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
                default: throw IndexedDBBytes.Failure.malformed
                }
                properties.append((key, try value(depth: depth + 1)))
            }
        }

        private mutating func double() throws -> Double {
            let slice = try reader.take(8)
            return Double(bitPattern: slice.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) })
        }

        private mutating func begin() -> Int {
            objects.append(nil)
            return objects.count - 1
        }

        private mutating func end(_ id: Int, _ value: JSValue) -> JSValue {
            objects[id] = value
            return value
        }
    }
}
