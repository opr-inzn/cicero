import Foundation

extension DocumentFonts {
    // MARK: Photoshop

    static func photoshop(_ data: Data) throws -> [DocumentFont] {
        var reader = PhotoshopReader(data)
        guard reader.bytes(4) == Array("8BPS".utf8), let version = reader.uint(2), version == 1 || version == 2 else {
            throw Failure.unreadable
        }
        let isLarge = version == 2
        reader.skip(20)
        for _ in 0..<2 {
            guard let length = reader.uint(4) else { throw Failure.unreadable }
            reader.skip(length)
        }
        guard reader.uint(isLarge ? 8 : 4) != nil, let layerInfo = reader.uint(isLarge ? 8 : 4), layerInfo > 0,
              let count = reader.int16()
        else { return [] }
        var fonts: [DocumentFont] = []
        // A negative count says the first alpha channel is the merged image's transparency.
        for _ in 0..<abs(Int(count)) {
            reader.skip(16)
            guard let channels = reader.uint(2) else { break }
            reader.skip(channels * (2 + (isLarge ? 8 : 4)))
            reader.skip(12)
            guard let extra = reader.uint(4) else { break }
            let end = reader.offset + extra
            for _ in 0..<2 { reader.skip(reader.uint(4) ?? extra) }
            guard let nameLength = reader.uint(1) else { break }
            reader.skip((nameLength + 1 + 3) / 4 * 4 - 1)
            while reader.offset + 12 <= end {
                guard let signature = reader.bytes(4), signature == Array("8BIM".utf8) || signature == Array("8B64".utf8),
                      let key = reader.bytes(4).flatMap({ String(bytes: $0, encoding: .ascii) }),
                      let length = reader.uint(isLarge && Self.longLayerInfoKeys.contains(key) ? 8 : 4)
                else { break }
                let start = reader.offset
                if key == "TySh", start + length <= min(end, data.count) {
                    fonts += textLayerFonts(Array(data[data.startIndex + start ..< data.startIndex + start + length]))
                }
                reader.offset = start + length
            }
            reader.offset = end
        }
        return fonts
    }

    private static let longLayerInfoKeys: Set<String> = [
        "LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk", "lnk2", "FEid", "FXid", "PxSD",
    ]

    static func textLayerFonts(_ bytes: [UInt8]) -> [DocumentFont] {
        guard let resources = find("/ResourceDict", in: bytes),
              let fontSet = find("/FontSet", in: bytes, from: resources)
        else { return [] }
        let names = fontNames(bytes, from: fontSet)
        // The font list names every font the layer has, with Photoshop's defaults among them: only those its runs name are used.
        var used = Set<Int>()
        if let runs = find("/StyleRun", in: bytes), runs < resources {
            let region = Array(bytes[runs..<resources])
            let named = numbers(after: "/Font", in: region)
            used.formUnion(named)
            if named.count < occurrences(of: "/RunLength", in: region), let sheets = find("/StyleSheetSet", in: bytes, from: resources),
               sheets < fontSet, let font = numbers(after: "/Font", in: Array(bytes[sheets..<fontSet])).first {
                used.insert(font)
            }
        }
        return used.sorted().compactMap { index in
            // Never the invisible font Photoshop sets hidden characters in.
            guard names.indices.contains(index), names[index] != "AdobeInvisFont" else { return nil }
            return DocumentFont(postScriptName: names[index])
        }
    }

    private static func fontNames(_ bytes: [UInt8], from start: Int) -> [String] {
        var names: [String] = []
        var at = start
        let close = find("]", in: bytes, from: start) ?? bytes.count
        while let name = find("/Name", in: bytes, from: at), name < close {
            at = name + 5
            while at < bytes.count, bytes[at] == 0x20 || bytes[at] == 0x09 || bytes[at] == 0x0A || bytes[at] == 0x0D { at += 1 }
            guard at < bytes.count, bytes[at] == UInt8(ascii: "(") else { continue }
            at += 1
            var string: [UInt8] = []
            while at < bytes.count, bytes[at] != UInt8(ascii: ")") {
                if bytes[at] == UInt8(ascii: "\\"), at + 1 < bytes.count { at += 1 }
                string.append(bytes[at])
                at += 1
            }
            let text = string.starts(with: [0xFE, 0xFF])
                ? String(bytes: string.dropFirst(2), encoding: .utf16BigEndian)
                : String(bytes: string, encoding: .isoLatin1)
            names.append(text ?? "")
        }
        return names
    }

    private static func numbers(after key: String, in bytes: [UInt8]) -> [Int] {
        var found: [Int] = []
        var at = 0
        while let match = find(key, in: bytes, from: at) {
            at = match + key.utf8.count
            var digits = at
            while digits < bytes.count, bytes[digits] == 0x20 || bytes[digits] == 0x09 { digits += 1 }
            guard digits > at else { continue }
            var value = 0
            var any = false
            while digits < bytes.count, (0x30...0x39).contains(bytes[digits]), value < 1_000_000 {
                value = value * 10 + Int(bytes[digits] - 0x30)
                any = true
                digits += 1
            }
            if any { found.append(value) }
        }
        return found
    }

    private static func occurrences(of key: String, in bytes: [UInt8]) -> Int {
        var count = 0
        var at = 0
        while let match = find(key, in: bytes, from: at) {
            count += 1
            at = match + 1
        }
        return count
    }

    private static func find(_ key: String, in bytes: [UInt8], from start: Int = 0) -> Int? {
        let needle = Array(key.utf8)
        guard let first = needle.first, start >= 0, bytes.count >= needle.count else { return nil }
        var at = start
        while at <= bytes.count - needle.count {
            if bytes[at] == first, bytes[at..<at + needle.count].elementsEqual(needle) { return at }
            at += 1
        }
        return nil
    }
}

private struct PhotoshopReader {
    private let data: Data
    var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func skip(_ count: Int) {
        offset = count > data.count - offset ? data.count : offset + max(count, 0)
    }

    mutating func bytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, offset + count <= data.count else { return nil }
        let start = data.startIndex + offset
        offset += count
        return Array(data[start..<start + count])
    }

    mutating func uint(_ count: Int) -> Int? {
        guard let bytes = bytes(count) else { return nil }
        var value: UInt64 = 0
        for byte in bytes { value = value << 8 | UInt64(byte) }
        return value <= UInt64(Int32.max) * 1024 ? Int(value) : nil
    }

    mutating func int16() -> Int16? {
        uint(2).map { Int16(bitPattern: UInt16($0)) }
    }
}
