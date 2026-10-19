import Foundation

/// A file's size and modification time (whole milliseconds), which decide whether its cached faces are current.
struct FaceStamp: Hashable, Sendable {
    var modified: Int64
    var size: Int64

    init(modified: Date, size: Int64) {
        self.modified = Int64((modified.timeIntervalSince1970 * 1000).rounded())
        self.size = size
    }

    init(modified: Int64, size: Int64) {
        self.modified = modified
        self.size = size
    }
}

/// What was read from one font file.
struct CachedFile: Hashable, Sendable {
    var stamp: FaceStamp
    var dateAdded: Date?
    /// Empty when CoreText couldn't read the file.
    var faces: [FontFace]
}

extension Classification {
    /// The classifications a face's PANOSE digits or letters can say, in the order the caches number them.
    fileprivate static let saved: [Classification] = [.serif, .sansSerif, .monospaced, .script, .ornamental, .symbol]
}

/// The on-disk face cache: a flat little-endian binary file. It's read once per launch and must be
/// fast; a hand-written layout decodes in a few milliseconds where Codable takes tens.
enum FaceCache {
    private static let magic: UInt32 = 0x4346_5450  // "PTFC"
    /// Part of the library cache's version too, as it writes faces the same way.
    static let version: UInt32 = 10
    /// Laid out like this version, but without `FontFace.isAtOrigin`: its variable fonts are read again.
    private static let withoutOrigins: UInt32 = 9

    static func encode(_ files: [String: CachedFile]) -> Data {
        var writer = ByteWriter()
        writer.write(magic)
        writer.write(version)
        writer.write(UInt32(files.count))
        for (path, file) in files {
            writer.write(path)
            writer.write(file.stamp.modified)
            writer.write(file.stamp.size)
            // Reference-date intervals round-trip exactly, so cached dates hash like fresh ones.
            writer.write(file.dateAdded?.timeIntervalSinceReferenceDate)
            writer.write(UInt32(file.faces.count))
            for face in file.faces { writer.write(face) }
        }
        return writer.data
    }

    /// nil when the data isn't a cache this version understands.
    static func decode(_ data: Data) -> [String: CachedFile]? {
        data.withUnsafeBytes { buffer -> [String: CachedFile]? in
            var reader = ByteReader(buffer: buffer)
            do {
                guard try reader.u32() == magic else { return nil }
                let saved = try reader.u32()
                guard saved == version || saved == withoutOrigins else { return nil }
                let count = Int(try reader.u32())
                var files: [String: CachedFile] = [:]
                files.reserveCapacity(count)
                for _ in 0..<count {
                    let path = try reader.string()
                    let stamp = FaceStamp(modified: try reader.i64(), size: try reader.i64())
                    let dateAdded = try reader.optionalDouble().map { Date(timeIntervalSinceReferenceDate: $0) }
                    let faceCount = Int(try reader.u32())
                    var faces: [FontFace] = []
                    faces.reserveCapacity(faceCount)
                    for _ in 0..<faceCount { faces.append(try reader.face(path: path)) }
                    if saved == withoutOrigins && faces.contains(where: { $0.weightAxis != nil || !$0.axes.isEmpty }) { continue }
                    files[path] = CachedFile(stamp: stamp, dateAdded: dateAdded, faces: faces)
                }
                return files
            } catch {
                return nil
            }
        }
    }
}

/// Little-endian values, and strings as a length and UTF-8; optionals start with 0 (nil) or 1.
struct ByteWriter {
    var data = Data()

    mutating func write(_ value: UInt8) {
        data.append(value)
    }

    mutating func write(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Int64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Double) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Double?) {
        guard let value else { return write(UInt8(0)) }
        write(UInt8(1))
        write(value)
    }

    mutating func write(_ string: String) {
        var string = string
        string.withUTF8 { bytes in
            write(UInt32(bytes.count))
            data.append(contentsOf: bytes)
        }
    }

    mutating func write(_ string: String?) {
        guard let string else { return write(UInt8(0)) }
        write(UInt8(1))
        write(string)
    }

    mutating func write(_ id: UUID) {
        withUnsafeBytes(of: id.uuid) { data.append(contentsOf: $0) }
    }

    /// 0 for none, else its place in `Classification.saved` plus one.
    mutating func write(_ classification: Classification?) {
        write(UInt8(classification.flatMap { Classification.saved.firstIndex(of: $0) }.map { $0 + 1 } ?? 0))
    }

    /// Everything but the face's path, which the face cache writes once per file.
    mutating func write(_ face: FontFace) {
        write(UInt32(face.id.index))
        write(face.postScriptName)
        write(face.familyName)
        write(face.styleName)
        write(face.fullName)
        write(UInt32(face.weight))
        write(UInt8(face.familyClass))
        write(face.panose)
        write(face.letterShape)
        write(UInt8((face.isItalic ? 1 : 0) | (face.isMonospaced ? 2 : 0) | (face.isAtOrigin ? 4 : 0)))
        write(face.manufacturer)
        write(face.version)
        write(face.designer)
        write(face.vendorID)
        write(face.weightAxis?.minimum)
        write(face.weightAxis?.maximum)
        write(face.weightAxis?.defaultValue)
        write(UInt8(face.width))
        write(UInt32(face.axes.count))
        for axis in face.axes {
            write(axis.tag)
            write(axis.name)
            write(axis.value)
        }
        write(UInt32(face.year ?? 0))
        write(UInt8(face.embedding.map { $0.rank + 1 } ?? 0))
        write(Int64(bitPattern: face.features.rawValue))
        write(UInt32(face.localizedFamilyNames.count))
        for (language, name) in face.localizedFamilyNames.sorted(by: { $0.key < $1.key }) {
            write(language)
            write(name)
        }
    }
}

struct ByteReader {
    struct Truncated: Error {}

    let buffer: UnsafeRawBufferPointer
    var offset = 0

    init(buffer: UnsafeRawBufferPointer) {
        self.buffer = buffer
    }

    /// Whether everything has been read.
    var isAtEnd: Bool { offset >= buffer.count }

    private mutating func take(_ count: Int) throws -> Int {
        guard count >= 0, offset + count <= buffer.count else { throw Truncated() }
        defer { offset += count }
        return offset
    }

    mutating func u8() throws -> UInt8 {
        buffer[try take(1)]
    }

    mutating func u32() throws -> UInt32 {
        UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: try take(4), as: UInt32.self))
    }

    mutating func i64() throws -> Int64 {
        Int64(littleEndian: buffer.loadUnaligned(fromByteOffset: try take(8), as: Int64.self))
    }

    mutating func double() throws -> Double {
        Double(bitPattern: UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: try take(8), as: UInt64.self)))
    }

    mutating func optionalDouble() throws -> Double? {
        try u8() == 1 ? try double() : nil
    }

    mutating func string() throws -> String {
        let count = Int(try u32())
        let start = try take(count)
        return String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<start + count]), as: UTF8.self)
    }

    mutating func optionalString() throws -> String? {
        try u8() == 1 ? try string() : nil
    }

    mutating func uuid() throws -> UUID {
        UUID(uuid: buffer.loadUnaligned(fromByteOffset: try take(16), as: uuid_t.self))
    }

    mutating func classification() throws -> Classification? {
        let code = Int(try u8())
        guard code > 0 else { return nil }
        guard code <= Classification.saved.count else { throw Truncated() }
        return Classification.saved[code - 1]
    }

    /// A face as `ByteWriter` writes it, from the file at `path`.
    mutating func face(path: String) throws -> FontFace {
        let index = Int(try u32())
        let postScriptName = try string()
        let familyName = try string()
        let styleName = try string()
        let fullName = try string()
        let weight = Int(try u32())
        let familyClass = Int(try u8())
        let panose = try classification()
        let letterShape = try classification()
        let flags = try u8()
        let manufacturer = try optionalString()
        let version = try optionalString()
        let designer = try optionalString()
        let vendorID = try optionalString()
        let minimum = try optionalDouble()
        let maximum = try optionalDouble()
        let defaultValue = try optionalDouble()
        let width = Int(try u8())
        let axisCount = Int(try u32())
        var axes: [VariationAxis] = []
        for _ in 0..<axisCount {
            axes.append(VariationAxis(tag: try string(), name: try string(), value: try double()))
        }
        let year = Int(try u32())
        let embedding = Int(try u8())
        guard embedding <= Embedding.allCases.count else { throw Truncated() }
        let features = OpenTypeFeatures(rawValue: UInt64(bitPattern: try i64()))
        var localizedFamilyNames: [String: String] = [:]
        for _ in 0..<Int(try u32()) {
            let language = try string()
            localizedFamilyNames[language] = try string()
        }
        var axis: WeightAxis?
        if let minimum, let maximum, let defaultValue {
            axis = WeightAxis(minimum: minimum, maximum: maximum, defaultValue: defaultValue)
        }
        return FontFace(
            id: FaceID(path: path, index: index), postScriptName: postScriptName, familyName: familyName,
            styleName: styleName, fullName: fullName, weight: weight, isItalic: flags & 1 != 0,
            isMonospaced: flags & 2 != 0, familyClass: familyClass, panose: panose, letterShape: letterShape, manufacturer: manufacturer,
            version: version, designer: designer, vendorID: vendorID, weightAxis: axis, width: width, axes: axes,
            isAtOrigin: flags & 4 != 0, year: year == 0 ? nil : year, embedding: embedding == 0 ? nil : Embedding.allCases[embedding - 1], features: features,
            localizedFamilyNames: localizedFamilyNames
        )
    }
}
