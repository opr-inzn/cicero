import CoreText
import Foundation

/// Reads a font file's faces with CoreText, without registering it.
enum FontFileReader {
    static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "dfont", "woff", "woff2"]

    /// Empty when CoreText can't read the file.
    static func faces(atPath path: String) -> [FontFace] {
        read(atPath: path).faces
    }

    /// The faces, and the descriptors they were read from; both empty when CoreText can't read the file.
    static func read(atPath path: String) -> (faces: [FontFace], descriptors: [CTFontDescriptor]) {
        let descriptors = FontFiles.descriptors(at: path)
        var axes: [Data: [[String: Any]]] = [:]
        var faces: [FontFace] = []
        for (index, descriptor) in descriptors.enumerated() {
            if let face = face(from: descriptor, id: FaceID(path: path, index: index), axes: &axes) { faces.append(face) }
        }
        return (faces, descriptors)
    }

    /// Finder's Date Added, else the creation date.
    static func dateAdded(atPath path: String) -> Date? {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    /// - Parameter axes: the variation axes read so far from the file's faces, by their fvar table.
    private static func face(from descriptor: CTFontDescriptor, id: FaceID, axes knownAxes: inout [Data: [[String: Any]]]) -> FontFace? {
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let postScriptName = CTFontCopyPostScriptName(font) as String
        guard !postScriptName.isEmpty else { return nil }
        let familyName = CTFontCopyFamilyName(font) as String
        let styleName = name(kCTFontStyleNameKey, of: font) ?? "Regular"
        let fullName = CTFontCopyFullName(font) as String
        let symbolic = CTFontGetSymbolicTraits(font)
        let lowercasedStyle = styleName.lowercased()
        var axis: WeightAxis?
        var axes: [VariationAxis] = []
        // A named instance's own coordinates; axes it leaves out are at their defaults. (The font's variation
        // would also hold the optical size CoreText picks for its point size.)
        let instance = (CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [NSNumber: NSNumber] ?? [:])
            .reduce(into: [UInt32: Double]()) { $0[$1.key.uint32Value] = $1.value.doubleValue }
        for entry in variationAxes(of: font, known: &knownAxes) {
            guard let identifier = (entry[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value,
                  let defaultValue = entry[kCTFontVariationAxisDefaultValueKey as String] as? Double
            else { continue }
            if identifier == weightAxisTag,
               let minimum = entry[kCTFontVariationAxisMinimumValueKey as String] as? Double,
               let maximum = entry[kCTFontVariationAxisMaximumValueKey as String] as? Double {
                axis = WeightAxis(minimum: minimum, maximum: maximum, defaultValue: defaultValue)
            }
            if entry[kCTFontVariationAxisHiddenKey as String] as? Bool == true { continue }
            let tag = String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: identifier >> $0) }, encoding: .isoLatin1) ?? ""
            let name = (entry[kCTFontVariationAxisNameKey as String] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            axes.append(VariationAxis(tag: tag, name: name.isEmpty ? tag : name, value: instance[identifier] ?? defaultValue))
        }
        let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), CTFontTableOptions(rawValue: 0)) as Data?
        let head = CTFontCopyTable(font, CTFontTableTag(kCTFontTableHead), CTFontTableOptions(rawValue: 0)) as Data?
        let familyClass = Int((symbolic.rawValue >> 28) & 0xF)
        let isMonospaced = symbolic.contains(.monoSpaceTrait)
        return FontFace(
            id: id, postScriptName: postScriptName, familyName: familyName, styleName: styleName, fullName: fullName,
            weight: weightClass(of: font, os2: os2),
            isItalic: symbolic.contains(.italicTrait) || lowercasedStyle.contains("italic") || lowercasedStyle.contains("oblique"),
            isMonospaced: isMonospaced,
            familyClass: familyClass,
            panose: panose(os2),
            // The letters are looked at only when the file doesn't say what the face is.
            letterShape: familyClass == 0 && !isMonospaced ? LetterShapes.classification(of: font) : nil,
            manufacturer: name(kCTFontManufacturerNameKey, of: font),
            version: name(kCTFontVersionNameKey, of: font),
            designer: name(kCTFontDesignerNameKey, of: font),
            vendorID: vendorID(os2),
            weightAxis: axis,
            width: widthClass(os2),
            axes: axes,
            year: year(copyright: name(kCTFontCopyrightNameKey, of: font), created: created(head))
        )
    }

    /// The font's variation axes, none without an fvar table. A variable font's named instances are faces of one font
    /// and share its axes, and CoreText looks up every axis's localized name, under a lock all reading threads
    /// wait on, for each of them: a file of fifty instances read its axes fifty times, and axes were a quarter of
    /// reading a library.
    private static func variationAxes(of font: CTFont, known: inout [Data: [[String: Any]]]) -> [[String: Any]] {
        guard let fvar = CTFontCopyTable(font, CTFontTableTag(kCTFontTableFvar), CTFontTableOptions(rawValue: 0)) as Data? else { return [] }
        if let axes = known[fvar] { return axes }
        let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
        known[fvar] = axes
        return axes
    }

    /// When a face came out, as near as its file says: the earliest year in its copyright notice ("© 2014–2021"
    /// is 2014), else the year the head table says the file was made. Nil when neither gives a likely year.
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

    /// Made once: a regex literal is compiled each time it's evaluated, which was most of the time `year` took.
    private nonisolated(unsafe) static let yearPattern = /(?:^|[^0-9])((?:19|20)[0-9]{2})(?![0-9])/
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The head table's created date: seconds since the start of 1904, big-endian, 20 bytes in.
    static func created(_ table: Data?) -> Date? {
        guard let table, table.count >= 28 else { return nil }
        let seconds = table[(table.startIndex + 20)..<(table.startIndex + 28)].reduce(Int64(0)) { $0 << 8 | Int64($1) }
        return Date(timeIntervalSince1970: TimeInterval(seconds) - 2_082_844_800)
    }

    private static let weightAxisTag: UInt32 = 0x7767_6874  // 'wght'

    private static func name(_ key: CFString, of font: CTFont) -> String? {
        guard let value = CTFontCopyName(font, key) as String? else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// OS/2 usWeightClass when it's in range, else the nearest class to CoreText's weight trait.
    private static func weightClass(of font: CTFont, os2 table: Data?) -> Int {
        if let table, table.count >= 6 {
            let weight = Int(table[table.startIndex + 4]) << 8 | Int(table[table.startIndex + 5])
            if (1...1000).contains(weight) { return weight }
        }
        let traits = CTFontCopyTraits(font) as NSDictionary
        let trait = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
        // AppKit's weight scale: ultraLight -0.8 … regular 0 … black 0.62.
        let scale: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return scale.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
    }

    /// OS/2 achVendID without its padding; nil when it's blank or isn't printable ASCII.
    static func vendorID(_ table: Data?) -> String? {
        guard let table, table.count >= 62 else { return nil }
        let bytes = table[(table.startIndex + 58)..<(table.startIndex + 62)]
        guard bytes.allSatisfy({ $0 == 0 || (0x20...0x7E).contains($0) }) else { return nil }
        let id = String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    /// What the OS/2 PANOSE digits say: the kind of font, and for text faces the serif style. Flared and rounded
    /// serifs could go either way, and the proportion digit often says monospaced of fonts that aren't.
    static func panose(_ table: Data?) -> Classification? {
        guard let table, table.count >= 34 else { return nil }
        let kind = table[table.startIndex + 32], serifStyle = table[table.startIndex + 33]
        switch kind {
        case 2:  // Latin text
            switch serifStyle {
            case 2...10: return .serif  // cove, square, thin, oval, exaggerated, triangle
            case 11...13: return .sansSerif  // normal, obtuse and perpendicular sans
            default: return nil
            }
        case 3: return .script  // Latin hand written
        case 4: return .ornamental  // Latin decorative
        case 5: return .symbol  // Latin symbol
        default: return nil
        }
    }

    /// OS/2 usWidthClass when it's in range, else normal.
    private static func widthClass(_ table: Data?) -> Int {
        guard let table, table.count >= 8 else { return 5 }
        let width = Int(table[table.startIndex + 6]) << 8 | Int(table[table.startIndex + 7])
        return (1...9).contains(width) ? width : 5
    }
}
