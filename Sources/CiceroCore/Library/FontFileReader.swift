import CoreText
import Foundation

enum FontFileReader {
    static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "dfont"]

    static func faces(atPath path: String) -> [FontFace] {
        read(atPath: path).faces
    }

    static func read(atPath path: String) -> (faces: [FontFace], descriptors: [CTFontDescriptor]) {
        let descriptors = FontFiles.descriptors(at: path)
        var axes: [Data: [[String: Any]]] = [:]
        var faces: [ReadFace] = []
        for (index, descriptor) in descriptors.enumerated() {
            if let face = face(from: descriptor, id: FaceID(path: path, index: index), axes: &axes) { faces.append(face) }
        }
        return (withoutAddedDefaults(faces), descriptors)
    }

    struct ReadFace {
        var face: FontFace
        var fvar: Data?
        var isAddedDefault: Bool
    }

    static func withoutAddedDefaults(_ faces: [ReadFace]) -> [FontFace] {
        // CoreText adds a variable font's default as one more face, a second Regular, when no named instance is at it; it stays when none is at the origin on every axis but weight, as in fonts whose instances, uprights too, say a slant of -32768, which leaves the default the only upright.
        faces.filter { read in
            !read.isAddedDefault || !faces.contains { !$0.isAddedDefault && $0.fvar == read.fvar && $0.face.isAtOrigin }
        }.map(\.face)
    }

    static func dateAdded(atPath path: String) -> Date? {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    private static func face(from descriptor: CTFontDescriptor, id: FaceID, axes knownAxes: inout [Data: [[String: Any]]]) -> ReadFace? {
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let postScriptName = CTFontCopyPostScriptName(font) as String
        guard !postScriptName.isEmpty else { return nil }
        let familyName = CTFontCopyFamilyName(font) as String
        let styleName = name(kCTFontStyleNameKey, of: font) ?? "Regular"
        let fullName = CTFontCopyFullName(font) as String
        let nameTable = CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?
        let names = NameTable(nameTable)
        let symbolic = CTFontGetSymbolicTraits(font)
        let lowercasedStyle = styleName.lowercased()
        var axis: WeightAxis?
        var axes: [VariationAxis] = []
        var isAtOrigin = true
        // A named instance's own coordinates, with axes it leaves out at their defaults; the font's variation would also hold the optical size CoreText picks for its point size.
        let instance = (CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber] ?? [:])
            .reduce(into: [UInt32: Double]()) { $0[$1.key.uint32Value] = $1.value.doubleValue }
        let fvar = CTFontCopyTable(font, CTFontTableTag(kCTFontTableFvar), []) as Data?
        let entries = variationAxes(of: font, fvar: fvar, known: &knownAxes)
        for entry in entries {
            guard let identifier = (entry[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value,
                  let defaultValue = entry[kCTFontVariationAxisDefaultValueKey as String] as? Double
            else { continue }
            if identifier != AxisTag.weight, abs((instance[identifier] ?? defaultValue) - defaultValue) > 0.01 { isAtOrigin = false }
            if identifier == AxisTag.weight,
               let minimum = entry[kCTFontVariationAxisMinimumValueKey as String] as? Double,
               let maximum = entry[kCTFontVariationAxisMaximumValueKey as String] as? Double {
                axis = WeightAxis(minimum: minimum, maximum: maximum, defaultValue: defaultValue)
            }
            if entry[kCTFontVariationAxisHiddenKey as String] as? Bool == true { continue }
            let tag = AxisTag.string(identifier)
            axes.append(VariationAxis(tag: tag, name: entry[kCTFontVariationAxisNameKey as String] as? String ?? "",
                                      value: instance[identifier] ?? defaultValue))
        }
        let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?
        let head = CTFontCopyTable(font, CTFontTableTag(kCTFontTableHead), []) as Data?
        let familyClass = Int((symbolic.rawValue >> 28) & 0xF)
        let isMonospaced = symbolic.contains(.monoSpaceTrait)
        let features = OpenTypeFeatures(tags: featureTags(CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []) as Data?))
        let face = FontFace(
            id: id, postScriptName: postScriptName, familyName: familyName, styleName: styleName, fullName: fullName,
            weight: weightClass(of: font, os2: os2),
            isItalic: symbolic.contains(.italicTrait) || lowercasedStyle.contains("italic") || lowercasedStyle.contains("oblique"),
            isMonospaced: isMonospaced,
            familyClass: familyClass,
            panose: panose(os2),
            letterShape: familyClass == 0 && !isMonospaced ? LetterShapes.classification(of: font) : nil,
            manufacturer: name(8, kCTFontManufacturerNameKey, in: names, of: font),
            version: name(5, kCTFontVersionNameKey, in: names, of: font),
            designer: name(9, kCTFontDesignerNameKey, in: names, of: font),
            vendorID: vendorID(os2),
            weightAxis: axis,
            width: widthClass(os2),
            axes: axes,
            isAtOrigin: isAtOrigin && !entries.isEmpty,
            year: year(copyright: name(0, kCTFontCopyrightNameKey, in: names, of: font), created: created(head)),
            embedding: embedding(os2),
            features: features,
            figures: figures(of: font, features: features),
            localizedFamilyNames: LocalizedNames.familyNames(nameTable, besides: familyName)
        )
        return ReadFace(face: face, fvar: fvar, isAddedDefault: instance.isEmpty && fvar.map(leavesDefaultUnnamed) == true)
    }

    static func figures(of font: CTFont, features: OpenTypeFeatures) -> Figures {
        let characters = Array("0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, glyphs.count), !glyphs.contains(0) else { return [] }
        var figures: Figures = []
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let width = advances[0].width
        if features.contains(.tabularFigures) || width > 0 && advances.allSatisfy({ abs($0.width - width) < width * 0.01 }) {
            figures.insert(.tabular)
        }
        var boxes = [CGRect](repeating: .zero, count: glyphs.count)
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &boxes, glyphs.count)
        let tall = max(boxes[6].maxY, boxes[8].maxY)
        let small = [0, 1, 2].map { boxes[$0].maxY }.max() ?? 0
        let descending = [3, 4, 5, 7, 9].count { boxes[$0].minY < -0.08 * tall }
        if features.contains(.oldStyleFigures) || tall > 0 && small < 0.8 * tall && descending >= 3 {
            figures.insert(.oldStyle)
        }
        guard CTFontCopyTable(font, CTFontTableTag(morxTag), []) != nil else { return figures }
        for type in CTFontCopyFeatures(font) as? [[String: Any]] ?? [] {
            let selectors = (type[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? [])
                .compactMap { $0[kCTFontFeatureSelectorIdentifierKey as String] as? Int }
            switch type[kCTFontFeatureTypeIdentifierKey as String] as? Int {
            case kNumberSpacingType where selectors.contains(kMonospacedNumbersSelector): figures.insert(.tabular)
            case kNumberCaseType where selectors.contains(kLowerCaseNumbersSelector): figures.insert(.oldStyle)
            default: break
            }
        }
        return figures
    }

    private static let morxTag: UInt32 = 0x6D6F_7278

    static func embedding(_ table: Data?) -> Embedding? {
        guard let table, table.count >= 10 else { return nil }
        return Embedding(fsType: UInt16(table[table.startIndex + 8]) << 8 | UInt16(table[table.startIndex + 9]))
    }

    static func featureTags(_ table: Data?) -> Set<String> {
        guard let table, table.count >= 10 else { return [] }
        func u16(_ offset: Int) -> Int { Int(table[table.startIndex + offset]) << 8 | Int(table[table.startIndex + offset + 1]) }
        let list = u16(6)
        guard list > 0, list + 2 <= table.count else { return [] }
        var tags = Set<String>()
        for record in 0..<u16(list) {
            let start = list + 2 + record * 6
            guard start + 4 <= table.count else { break }
            let bytes = table[(table.startIndex + start)..<(table.startIndex + start + 4)]
            tags.insert(String(decoding: bytes, as: UTF8.self))
        }
        return tags
    }

    private static func variationAxes(of font: CTFont, fvar: Data?, known: inout [Data: [[String: Any]]]) -> [[String: Any]] {
        guard let fvar else { return [] }
        if let axes = known[fvar] { return axes }
        let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
        known[fvar] = axes
        return axes
    }

    static func leavesDefaultUnnamed(_ fvar: Data) -> Bool {
        guard fvar.count >= 16 else { return false }
        func u16(_ offset: Int) -> Int { Int(fvar[fvar.startIndex + offset]) << 8 | Int(fvar[fvar.startIndex + offset + 1]) }
        func fixed(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
        let axesStart = u16(4), axisCount = u16(8), axisSize = u16(10), instanceCount = u16(12), instanceSize = u16(14)
        let instancesStart = axesStart + axisCount * axisSize
        guard axisCount > 0, instanceCount > 0, axisSize >= 20, instanceSize >= 4 + axisCount * 4,
              instancesStart + instanceCount * instanceSize <= fvar.count
        else { return false }
        let defaults = (0..<axisCount).map { fixed(axesStart + $0 * axisSize + 8) }
        // Compared as written, as CoreText does: an instance at slant 0 on an axis that only goes to -16 draws like the default, but isn't at it.
        return !(0..<instanceCount).contains { instance in
            (0..<axisCount).map { fixed(instancesStart + instance * instanceSize + 4 + $0 * 4) } == defaults
        }
    }

    static func year(copyright: String?, created: Date?) -> Int? {
        let calendar = utcCalendar
        let latest = calendar.component(.year, from: .now) + 1
        if let copyright {
            let years = copyright.matches(of: yearPattern).compactMap { Int($0.output.1) }
            if let earliest = years.filter({ (1950...latest).contains($0) }).min() { return earliest }
        }
        // Files that don't set it say 1904, when the head table's dates begin, or something as unlikely.
        guard let created else { return nil }
        let year = calendar.component(.year, from: created)
        return (1985...latest).contains(year) ? year : nil
    }

    private nonisolated(unsafe) static let yearPattern = /(?:^|[^0-9])((?:19|20)[0-9]{2})(?![0-9])/
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func created(_ table: Data?) -> Date? {
        guard let table, table.count >= 28 else { return nil }
        let seconds = table[(table.startIndex + 20)..<(table.startIndex + 28)].reduce(Int64(0)) { $0 << 8 | Int64($1) }
        return Date(timeIntervalSince1970: TimeInterval(seconds) - 2_082_844_800)
    }


    private static func name(_ nameID: Int, _ key: CFString, in names: NameTable?, of font: CTFont) -> String? {
        if let names, let name = names.name(nameID) { return name }
        return name(key, of: font)
    }

    private static func name(_ key: CFString, of font: CTFont) -> String? {
        guard let value = CTFontCopyName(font, key) as String? else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func weightClass(of font: CTFont, os2 table: Data?) -> Int {
        if let table, table.count >= 6 {
            let weight = Int(table[table.startIndex + 4]) << 8 | Int(table[table.startIndex + 5])
            if (1...1000).contains(weight) { return weight }
        }
        let traits = CTFontCopyTraits(font) as NSDictionary
        let trait = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
        let scale: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return scale.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
    }

    static func vendorID(_ table: Data?) -> String? {
        guard let table, table.count >= 62 else { return nil }
        let bytes = table[(table.startIndex + 58)..<(table.startIndex + 62)]
        guard bytes.allSatisfy({ $0 == 0 || (0x20...0x7E).contains($0) }) else { return nil }
        let id = String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    static func panose(_ table: Data?) -> Classification? {
        guard let table, table.count >= 34 else { return nil }
        // Not the proportion digit, which often says monospaced of fonts that aren't.
        let kind = table[table.startIndex + 32], serifStyle = table[table.startIndex + 33]
        switch kind {
        case 2:
            switch serifStyle {
            case 2...10: return .serif
            case 11...13: return .sansSerif
            default: return nil
            }
        case 3: return .script
        case 4: return .ornamental
        case 5: return .symbol
        default: return nil
        }
    }

    private static func widthClass(_ table: Data?) -> Int {
        guard let table, table.count >= 8 else { return 5 }
        let width = Int(table[table.startIndex + 6]) << 8 | Int(table[table.startIndex + 7])
        return (1...9).contains(width) ? width : 5
    }
}
