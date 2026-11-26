import CoreGraphics
import CoreText
import Foundation

public struct PDFEmbeddedFont: Sendable {
    public let fontData: Data
    public let glyphMap: [Character: CGGlyph]
    public let glyphNames: [Character: String]
    public let isCID: Bool

    public init(fontData: Data, glyphMap: [Character: CGGlyph], glyphNames: [Character: String] = [:], isCID: Bool) {
        self.fontData = fontData
        self.glyphMap = glyphMap
        self.glyphNames = glyphNames
        self.isCID = isCID
    }

    public func makeFont() -> (font: CTFont, glyphMap: ((Character) -> CGGlyph?)?)? {
        guard let provider = CGDataProvider(data: fontData as CFData),
              let cgFont = CGFont(provider) else { return nil }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, 1000, nil, nil)
        let directHits = LetterImages.letters.count { ctFont.glyph(for: $0) != nil }
        if directHits >= LetterImages.fewest { return (ctFont, nil) }
        var combined = glyphMap
        for (ch, name) in glyphNames where combined[ch] == nil {
            let g = CTFontGetGlyphWithName(ctFont, name as CFString)
            if g != 0 { combined[ch] = g }
        }
        // CFF / Type1C subsets often omit a cmap and ToUnicode, keeping standard PostScript glyph names instead.
        let candidates = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        for ch in candidates where combined[ch] == nil {
            if let name = Self.postScriptName(for: ch) {
                let g = CTFontGetGlyphWithName(ctFont, name as CFString)
                if g != 0 { combined[ch] = g }
            }
        }
        guard !combined.isEmpty else { return nil }
        let map = combined
        let lookup: (Character) -> CGGlyph? = { ch in map[ch] ?? ctFont.glyph(for: ch) }
        guard LetterImages.letters.count(where: { lookup($0) != nil }) >= LetterImages.fewest else { return nil }
        return (ctFont, lookup)
    }

    private static func postScriptName(for character: Character) -> String? {
        if character.isASCII && character.isLetter { return String(character) }
        switch character {
        case "0": return "zero"; case "1": return "one"; case "2": return "two"; case "3": return "three"; case "4": return "four"
        case "5": return "five"; case "6": return "six"; case "7": return "seven"; case "8": return "eight"; case "9": return "nine"
        default: return nil
        }
    }

    public static func extractAll(from url: URL) -> [String: PDFEmbeddedFont] {
        guard ["pdf", "ai"].contains(url.pathExtension.lowercased()),
              let document = CGPDFDocument(url as CFURL),
              !document.isEncrypted || document.unlockWithPassword("") else { return [:] }
        var collector = EmbeddedCollector()
        for number in stride(from: 1, through: document.numberOfPages, by: 1) {
            guard let page = document.page(at: number)?.dictionary else { continue }
            collector.resources(of: DocumentFonts.resourcesOwner(of: page))
            var annotations: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(page, "Annots", &annotations), let annotations {
                for index in 0..<CGPDFArrayGetCount(annotations) {
                    var annotation: CGPDFDictionaryRef?, appearances: CGPDFDictionaryRef?, normal: CGPDFStreamRef?
                    if CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
                       CGPDFDictionaryGetDictionary(annotation, "AP", &appearances), let appearances,
                       CGPDFDictionaryGetStream(appearances, "N", &normal), let normal,
                       let dictionary = CGPDFStreamGetDictionary(normal) {
                        collector.resources(of: dictionary)
                    }
                }
            }
        }
        return collector.extracted
    }
}

private struct EmbeddedCollector {
    var extracted: [String: PDFEmbeddedFont] = [:]
    private var seen = Set<Int>()
    private static let maxFontBytes = 16 * 1024 * 1024
    private static let maxMapBytes = 1024 * 1024

    mutating func resources(of owner: CGPDFDictionaryRef) {
        var found: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(owner, "Resources", &found), let resources = found,
              seen.insert(unsafeBitCast(resources, to: Int.self)).inserted, seen.count < 10_000 else { return }
        var fontDictionary: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fontDictionary), let fontDictionary {
            var pairs: [(String, PDFEmbeddedFont)] = []
            CGPDFDictionaryApplyBlock(fontDictionary, { _, object, _ in
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(object, .dictionary, &font), let font, let pair = Self.extractFont(font) {
                    pairs.append(pair)
                }
                return true
            }, nil)
            for (key, candidate) in pairs {
                if let existing = extracted[key], existing.fontData.count >= candidate.fontData.count
                    && (existing.glyphMap.count + existing.glyphNames.count) >= (candidate.glyphMap.count + candidate.glyphNames.count) {
                    continue
                }
                extracted[key] = candidate
            }
        }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return }
        var forms: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream),
               CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Form" {
                forms.append(dictionary)
            }
            return true
        }, nil)
        for form in forms { self.resources(of: form) }
    }

    private static func extractFont(_ font: CGPDFDictionaryRef) -> (String, PDFEmbeddedFont)? {
        var namePtr: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(font, "BaseFont", &namePtr), let namePtr else { return nil }
        var base = DocumentFonts.withoutSubsetTag(String(cString: namePtr))
        var descriptorOwner = font
        var isCID = false
        var descendants: CGPDFArrayRef?, descendant: CGPDFDictionaryRef?
        if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
           CGPDFArrayGetDictionary(descendants, 0, &descendant), let descendant {
            descriptorOwner = descendant
            isCID = true
            for suffix in ["-Identity-H", "-Identity-V"] where base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)) }
        }
        var descriptor: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(descriptorOwner, "FontDescriptor", &descriptor), let descriptor else { return nil }

        var rawData: Data?
        var isBareCFF = false
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(descriptor, "FontFile2", &stream), let stream {
            rawData = copyStream(stream, limit: maxFontBytes)
        } else if CGPDFDictionaryGetStream(descriptor, "FontFile3", &stream), let stream {
            if let data = copyStream(stream, limit: maxFontBytes) {
                var subPtr: UnsafePointer<CChar>?
                let sub = (CGPDFStreamGetDictionary(stream).flatMap { dict in
                    CGPDFDictionaryGetName(dict, "Subtype", &subPtr) ? subPtr.map { String(cString: $0) } : nil
                }) ?? ""
                if sub == "OpenType" || isSFNT(data) {
                    rawData = data
                } else if sub == "Type1C" || sub == "CIDFontType0C" || (data.count >= 4 && data[0] == 1 && data[1] == 0) {
                    isBareCFF = true
                    rawData = data
                }
            }
        }
        guard var fontData = rawData, !fontData.isEmpty else { return nil }
        let widths = isCID ? cidWidths(descriptorOwner) : simpleWidths(font)
        let cidMapping = isCID ? parseCIDToGID(descriptorOwner) : nil
        let encodingNames = isCID ? [:] : parseSimpleEncoding(font)
        var effectiveCIDToGID: [UInt32: CGGlyph]?
        var cidIsIdentity = false
        if case .map(let map) = cidMapping {
            effectiveCIDToGID = map
        } else if case .identity = cidMapping {
            cidIsIdentity = true
        }
        if isBareCFF {
            guard let info = SFNTWrapper.cffInfo(fontData) else { return nil }
            if isCID, effectiveCIDToGID == nil, let cffMap = info.cidToGID {
                effectiveCIDToGID = cffMap
                cidIsIdentity = false
            }
            let gidWidths: [Int: UInt16]
            if isCID {
                if let gidMap = effectiveCIDToGID {
                    var remapped: [Int: UInt16] = [:]
                    for (cid, width) in widths {
                        if cid >= 0, let gid = gidMap[UInt32(cid)], gid != 0 { remapped[Int(gid)] = width }
                    }
                    gidWidths = remapped
                } else if cidIsIdentity {
                    gidWidths = widths
                } else {
                    gidWidths = [:]
                }
            } else {
                gidWidths = [:]
            }
            guard var wrapped = SFNTWrapper.wrapCFF(fontData, numGlyphs: info.numGlyphs, widths: gidWidths) else { return nil }
            if !isCID, !widths.isEmpty,
               let provider = CGDataProvider(data: wrapped as CFData),
               let cgFont = CGFont(provider) {
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, 1000, nil, nil)
                var remapped: [Int: UInt16] = [:]
                for (code, width) in widths {
                    let name = encodingNames[code] ?? standardASCIIName(for: code)
                    if let name {
                        let gid = CTFontGetGlyphWithName(ctFont, name as CFString)
                        if gid != 0 { remapped[Int(gid)] = width }
                    }
                }
                if !remapped.isEmpty, let rewrapped = SFNTWrapper.wrapCFF(fontData, numGlyphs: info.numGlyphs, widths: remapped) {
                    wrapped = rewrapped
                }
            }
            fontData = wrapped
        }

        let toUnicode = parseToUnicode(font)
        var glyphMap: [Character: CGGlyph] = [:]
        var glyphNames: [Character: String] = [:]
        if isCID {
            for (code, ch) in toUnicode {
                if let gidMap = effectiveCIDToGID {
                    if let gid = gidMap[code], gid != 0 { glyphMap[ch] = gid }
                } else if cidIsIdentity, code > 0 && code < 65536 {
                    glyphMap[ch] = CGGlyph(code)
                }
            }
        } else {
            for (_, name) in encodingNames {
                if let ch = adobeGlyphNameToASCII(name) { glyphNames[ch] = name }
            }
            for (code, ch) in toUnicode {
                if let name = encodingNames[Int(code)] { glyphNames[ch] = name }
            }
        }
        return (base.lowercased(), PDFEmbeddedFont(fontData: fontData, glyphMap: glyphMap, glyphNames: glyphNames, isCID: isCID))
    }

    private static func isSFNT(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let b = [data[0], data[1], data[2], data[3]]
        return (b == [0, 1, 0, 0]) || (b == Array("OTTO".utf8)) || (b == Array("true".utf8))
    }

    private static func copyStream(_ stream: CGPDFStreamRef, limit: Int) -> Data? {
        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return nil }
        let data = cfData as Data
        return data.count <= limit ? data : nil
    }

    private enum CIDToGID {
        case identity
        case map([UInt32: CGGlyph])
    }

    private static func parseCIDToGID(_ descendant: CGPDFDictionaryRef) -> CIDToGID? {
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(descendant, "CIDToGIDMap", &stream), let stream, let data = copyStream(stream, limit: maxMapBytes) {
            var map: [UInt32: CGGlyph] = [:]
            let count = data.count / 2
            for cid in 0..<count {
                let gid = UInt16(data[cid * 2]) << 8 | UInt16(data[cid * 2 + 1])
                if gid != 0 { map[UInt32(cid)] = gid }
            }
            return .map(map)
        }
        var namePtr: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(descendant, "CIDToGIDMap", &namePtr), let namePtr, String(cString: namePtr) == "Identity" {
            return .identity
        }
        var subPtr: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(descendant, "Subtype", &subPtr), let subPtr, String(cString: subPtr) == "CIDFontType2" {
            return .identity
        }
        return nil
    }

    private static func parseToUnicode(_ font: CGPDFDictionaryRef) -> [UInt32: Character] {
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(font, "ToUnicode", &stream), let stream,
              let data = copyStream(stream, limit: maxMapBytes),
              let text = String(data: data, encoding: .isoLatin1) else { return [:] }
        var map: [UInt32: Character] = [:]
        let bfchar = #/beginbfchar([\s\S]*?)endbfchar/#
        for match in text.matches(of: bfchar) {
            let hexes = hexTokens(String(match.1))
            var i = 0
            while i + 1 < hexes.count {
                if let src = UInt32(hexes[i], radix: 16), let ch = unicodeChar(fromHex: hexes[i + 1]) {
                    map[src] = ch
                }
                i += 2
            }
        }
        let bfrange = #/beginbfrange([\s\S]*?)endbfrange/#
        for match in text.matches(of: bfrange) {
            let body = String(match.1)
            for line in body.split(whereSeparator: \.isNewline) {
                let s = String(line)
                if let bracket = s.firstIndex(of: "[") {
                    let head = hexTokens(String(s[..<bracket]))
                    let tail = hexTokens(String(s[bracket...]))
                    guard head.count >= 2, let lo = UInt32(head[0], radix: 16), let hi = UInt32(head[1], radix: 16), hi >= lo, hi - lo < 512 else { continue }
                    let limit = Int(hi - lo) + 1
                    for (offset, hex) in tail.prefix(limit).enumerated() {
                        if let ch = unicodeChar(fromHex: hex) { map[lo + UInt32(offset)] = ch }
                    }
                } else {
                    let hexes = hexTokens(s)
                    var i = 0
                    while i + 2 < hexes.count {
                        if let lo = UInt32(hexes[i], radix: 16), let hi = UInt32(hexes[i + 1], radix: 16),
                           let dst = UInt32(hexes[i + 2], radix: 16), hi >= lo, hi - lo < 512 {
                            for offset in 0...(hi - lo) {
                                let (codePoint, overflow) = dst.addingReportingOverflow(offset)
                                if !overflow, let scalar = UnicodeScalar(codePoint) { map[lo + offset] = Character(scalar) }
                            }
                        }
                        i += 3
                    }
                }
            }
        }
        return map
    }

    private static func hexTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current: String?
        for ch in text {
            if ch == "<" {
                current = ""
            } else if ch == ">", let token = current {
                if !token.isEmpty { tokens.append(token) }
                current = nil
            } else if current != nil && !ch.isWhitespace {
                current?.append(ch)
            }
        }
        return tokens
    }

    private static func unicodeChar(fromHex hex: String) -> Character? {
        guard hex.count == 4 || hex.count == 2, let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) else { return nil }
        return Character(scalar)
    }

    private static func parseSimpleEncoding(_ font: CGPDFDictionaryRef) -> [Int: String] {
        var enc: CGPDFDictionaryRef?, diffs: CGPDFArrayRef?
        guard CGPDFDictionaryGetDictionary(font, "Encoding", &enc), let enc,
              CGPDFDictionaryGetArray(enc, "Differences", &diffs), let diffs else { return [:] }
        var map: [Int: String] = [:]
        var code = 0
        for index in 0..<CGPDFArrayGetCount(diffs) {
            var num: CGPDFInteger = 0
            var namePtr: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(diffs, index, &num) {
                code = Int(num)
            } else if CGPDFArrayGetName(diffs, index, &namePtr), let namePtr {
                let name = String(cString: namePtr)
                if code >= 0 && code <= 65535 {
                    map[code] = name
                }
                if code < 65536 { code += 1 }
            }
        }
        return map
    }

    private static func standardASCIIName(for code: Int) -> String? {
        guard code >= 0x30 && code <= 0x7A, let scalar = UnicodeScalar(code) else { return nil }
        let ch = Character(scalar)
        if ch.isASCII && ch.isLetter { return String(ch) }
        switch ch {
        case "0": return "zero"; case "1": return "one"; case "2": return "two"; case "3": return "three"; case "4": return "four"
        case "5": return "five"; case "6": return "six"; case "7": return "seven"; case "8": return "eight"; case "9": return "nine"
        default: return nil
        }
    }

    private static func adobeGlyphNameToASCII(_ name: String) -> Character? {
        if name.count == 1, let ch = name.first, ch.isASCII && ch.isLetter { return ch }
        switch name {
        case "zero": return "0"; case "one": return "1"; case "two": return "2"; case "three": return "3"; case "four": return "4"
        case "five": return "5"; case "six": return "6"; case "seven": return "7"; case "eight": return "8"; case "nine": return "9"
        default: return nil
        }
    }

    private static func clampedWidth(_ value: CGPDFReal) -> UInt16? {
        guard value.isFinite else { return nil }
        return UInt16(min(65535.0, max(0.0, value.rounded())))
    }

    private static func cidWidths(_ descendant: CGPDFDictionaryRef) -> [Int: UInt16] {
        var widths: [Int: UInt16] = [:]
        var wArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(descendant, "W", &wArray), let wArray else { return widths }
        let count = CGPDFArrayGetCount(wArray)
        var i = 0
        while i + 1 < count {
            var startCID: CGPDFInteger = 0
            guard CGPDFArrayGetInteger(wArray, i, &startCID) else { i += 1; continue }
            var nested: CGPDFArrayRef?
            var endCID: CGPDFInteger = 0
            var widthVal: CGPDFReal = 0
            if CGPDFArrayGetArray(wArray, i + 1, &nested), let nested {
                if startCID >= 0, startCID <= 65535 {
                    for j in 0..<CGPDFArrayGetCount(nested) {
                        let (cid, overflow) = Int(startCID).addingReportingOverflow(j)
                        guard !overflow, cid <= 65535 else { break }
                        var w: CGPDFReal = 0
                        if CGPDFArrayGetNumber(nested, j, &w), let clamped = clampedWidth(w) {
                            widths[cid] = clamped
                        }
                    }
                }
                i += 2
            } else if i + 2 < count, CGPDFArrayGetInteger(wArray, i + 1, &endCID), CGPDFArrayGetNumber(wArray, i + 2, &widthVal) {
                if startCID >= 0, endCID >= startCID, endCID <= 65535, endCID - startCID < 4096, let clamped = clampedWidth(widthVal) {
                    for cid in startCID...endCID { widths[Int(cid)] = clamped }
                }
                i += 3
            } else {
                i += 1
            }
        }
        return widths
    }

    private static func simpleWidths(_ font: CGPDFDictionaryRef) -> [Int: UInt16] {
        var widths: [Int: UInt16] = [:]
        var firstChar: CGPDFInteger = 0
        var wArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetInteger(font, "FirstChar", &firstChar),
              firstChar >= 0, firstChar <= 65535,
              CGPDFDictionaryGetArray(font, "Widths", &wArray), let wArray else { return widths }
        for j in 0..<CGPDFArrayGetCount(wArray) {
            let (code, overflow) = Int(firstChar).addingReportingOverflow(j)
            guard !overflow, code <= 65535 else { break }
            var w: CGPDFReal = 0
            if CGPDFArrayGetNumber(wArray, j, &w), let clamped = clampedWidth(w) {
                widths[code] = clamped
            }
        }
        return widths
    }
}

private enum SFNTWrapper {
    struct CFFInfo {
        let numGlyphs: Int
        let cidToGID: [UInt32: CGGlyph]?
    }

    // CoreGraphics CGFont requires an OpenType SFNT container around bare PDF FontFile3 CFF streams.
    static func wrapCFF(_ cff: Data, numGlyphs: Int, widths: [Int: UInt16]) -> Data? {
        guard numGlyphs > 0, numGlyphs <= Int(UInt16.max) else { return nil }
        var head = Data(repeating: 0, count: 54)
        writeU32(&head, 0, 0x0001_0000)
        writeU32(&head, 12, 0x5F0F_3CF5)
        writeU16(&head, 18, 1000)
        writeI16(&head, 36, -200); writeI16(&head, 38, -300); writeI16(&head, 40, 1200); writeI16(&head, 42, 1000)
        writeU16(&head, 46, 8)

        var hhea = Data(repeating: 0, count: 36)
        writeU32(&hhea, 0, 0x0001_0000)
        writeI16(&hhea, 4, 800); writeI16(&hhea, 6, -200)
        writeU16(&hhea, 10, 1000)
        writeU16(&hhea, 34, UInt16(numGlyphs))

        var maxp = Data(repeating: 0, count: 6)
        writeU32(&maxp, 0, 0x0000_5000)
        writeU16(&maxp, 4, UInt16(numGlyphs))

        var hmtx = Data(repeating: 0, count: numGlyphs * 4)
        for gid in 0..<numGlyphs {
            writeU16(&hmtx, gid * 4, widths[gid] ?? 500)
        }

        let tables: [(String, Data)] = [
            ("CFF ", cff), ("head", head), ("hhea", hhea), ("hmtx", hmtx), ("maxp", maxp),
        ].sorted { $0.0 < $1.0 }

        let count = tables.count
        var out = Data()
        out.append(contentsOf: "OTTO".utf8)
        appendU16(&out, UInt16(count))
        appendU16(&out, 64); appendU16(&out, 2); appendU16(&out, UInt16(count * 16 - 64))
        var offset = 12 + count * 16
        var paddedBodies: [Data] = []
        for (tag, body) in tables {
            var padded = body
            while padded.count % 4 != 0 { padded.append(0) }
            out.append(contentsOf: tag.utf8)
            appendU32(&out, checksum(padded))
            appendU32(&out, UInt32(offset))
            appendU32(&out, UInt32(body.count))
            offset += padded.count
            paddedBodies.append(padded)
        }
        for body in paddedBodies { out.append(body) }
        return out
    }

    static func cffInfo(_ cff: Data) -> CFFInfo? {
        guard cff.count >= 4 else { return nil }
        var pos = Int(cff[2])
        func skipIndex() -> Bool {
            guard pos + 2 <= cff.count else { return false }
            let count = Int(cff[pos]) << 8 | Int(cff[pos + 1])
            pos += 2
            if count == 0 { return true }
            guard pos < cff.count else { return false }
            let offSize = Int(cff[pos])
            pos += 1
            guard offSize >= 1 && offSize <= 4 else { return false }
            let offsetsEnd = pos + (count + 1) * offSize
            guard offsetsEnd <= cff.count else { return false }
            var last = 0
            let lastStart = pos + count * offSize
            for i in 0..<offSize { last = (last << 8) | Int(cff[lastStart + i]) }
            guard last >= 1 else { return false }
            pos = offsetsEnd + last - 1
            return pos <= cff.count
        }
        guard skipIndex() else { return nil }
        guard pos + 2 <= cff.count else { return nil }
        let dictCount = Int(cff[pos]) << 8 | Int(cff[pos + 1])
        pos += 2
        guard dictCount >= 1, pos < cff.count else { return nil }
        let offSize = Int(cff[pos]); pos += 1
        guard offSize >= 1 && offSize <= 4, pos + (dictCount + 1) * offSize <= cff.count else { return nil }
        func readOff(_ at: Int) -> Int {
            var v = 0; for i in 0..<offSize { v = (v << 8) | Int(cff[at + i]) }; return v
        }
        let firstOff = readOff(pos)
        let secondOff = readOff(pos + offSize)
        guard firstOff >= 1, secondOff >= firstOff else { return nil }
        let dStart = pos + (dictCount + 1) * offSize + firstOff - 1
        let dEnd = pos + (dictCount + 1) * offSize + secondOff - 1
        guard dStart >= 0, dEnd <= cff.count, dStart < dEnd else { return nil }
        var stack: [Int] = []
        var p = dStart
        var charStringsOffset: Int?
        var charsetOffset: Int?
        var hasROS = false
        while p < dEnd {
            let b0 = Int(cff[p]); p += 1
            if b0 == 28, p + 2 <= dEnd {
                let v = Int(Int16(bitPattern: UInt16(cff[p]) << 8 | UInt16(cff[p + 1]))); p += 2
                stack.append(v)
            } else if b0 == 29, p + 4 <= dEnd {
                let v = Int(Int32(bitPattern: UInt32(cff[p]) << 24 | UInt32(cff[p + 1]) << 16 | UInt32(cff[p + 2]) << 8 | UInt32(cff[p + 3]))); p += 4
                stack.append(v)
            } else if b0 >= 32 && b0 <= 246 {
                stack.append(b0 - 139)
            } else if b0 >= 247 && b0 <= 250, p < dEnd {
                let b1 = Int(cff[p]); p += 1; stack.append((b0 - 247) * 256 + b1 + 108)
            } else if b0 >= 251 && b0 <= 254, p < dEnd {
                let b1 = Int(cff[p]); p += 1; stack.append(-(b0 - 251) * 256 - b1 - 108)
            } else if b0 == 30 {
                while p < dEnd { let nb = cff[p]; p += 1; if (nb & 0xF) == 0xF || (nb >> 4) == 0xF { break } }
                stack.append(0)
            } else if b0 == 12, p < dEnd {
                let b1 = Int(cff[p]); p += 1
                if b1 == 30 { hasROS = true }
                stack.removeAll()
            } else {
                if b0 == 15, let off = stack.last { charsetOffset = off }
                if b0 == 17, let off = stack.last { charStringsOffset = off }
                stack.removeAll()
            }
        }
        guard let csOff = charStringsOffset, csOff >= 0, csOff + 2 <= cff.count else { return nil }
        let numGlyphs = Int(cff[csOff]) << 8 | Int(cff[csOff + 1])
        guard numGlyphs > 0 else { return nil }
        let cidToGID = hasROS ? parseCIDCharset(cff, offset: charsetOffset, numGlyphs: numGlyphs) : nil
        return CFFInfo(numGlyphs: numGlyphs, cidToGID: cidToGID)
    }

    private static func parseCIDCharset(_ cff: Data, offset: Int?, numGlyphs: Int) -> [UInt32: CGGlyph]? {
        guard let offset, offset > 2, offset < cff.count else { return nil }
        let format = cff[offset]
        var p = offset + 1
        var gid = 1
        var map: [UInt32: CGGlyph] = [:]
        switch format {
        case 0:
            while gid < numGlyphs, p + 2 <= cff.count {
                let cid = UInt32(cff[p]) << 8 | UInt32(cff[p + 1])
                map[cid] = CGGlyph(gid)
                p += 2
                gid += 1
            }
        case 1:
            while gid < numGlyphs, p + 3 <= cff.count {
                let first = UInt32(cff[p]) << 8 | UInt32(cff[p + 1])
                let nLeft = Int(cff[p + 2])
                p += 3
                for k in 0...nLeft where gid < numGlyphs {
                    map[first + UInt32(k)] = CGGlyph(gid)
                    gid += 1
                }
            }
        case 2:
            while gid < numGlyphs, p + 4 <= cff.count {
                let first = UInt32(cff[p]) << 8 | UInt32(cff[p + 1])
                let nLeft = Int(cff[p + 2]) << 8 | Int(cff[p + 3])
                p += 4
                for k in 0...nLeft where gid < numGlyphs {
                    map[first + UInt32(k)] = CGGlyph(gid)
                    gid += 1
                }
            }
        default:
            return nil
        }
        return map.isEmpty ? nil : map
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        var i = 0
        while i + 3 < data.count {
            let word = UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
            sum = sum &+ word
            i += 4
        }
        return sum
    }

    private static func writeU16(_ d: inout Data, _ at: Int, _ v: UInt16) {
        d[at] = UInt8(v >> 8); d[at + 1] = UInt8(v & 0xFF)
    }
    private static func writeI16(_ d: inout Data, _ at: Int, _ v: Int16) {
        writeU16(&d, at, UInt16(bitPattern: v))
    }
    private static func writeU32(_ d: inout Data, _ at: Int, _ v: UInt32) {
        d[at] = UInt8((v >> 24) & 0xFF); d[at + 1] = UInt8((v >> 16) & 0xFF); d[at + 2] = UInt8((v >> 8) & 0xFF); d[at + 3] = UInt8(v & 0xFF)
    }
    private static func appendU16(_ d: inout Data, _ v: UInt16) { d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF)) }
    private static func appendU32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8((v >> 24) & 0xFF)); d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF))
    }
}
