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

/// The on-disk face cache: a flat little-endian binary file. It's read once per launch and must be
/// fast; a hand-written layout decodes in a few milliseconds where Codable takes tens.
enum FaceCache {
    private static let magic: UInt32 = 0x4346_5450  // "PTFC"
    private static let version: UInt32 = 4

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
            for face in file.faces {
                writer.write(UInt32(face.id.index))
                writer.write(face.postScriptName)
                writer.write(face.familyName)
                writer.write(face.styleName)
                writer.write(face.fullName)
                writer.write(UInt32(face.weight))
                writer.write(UInt8(face.familyClass))
                writer.write(UInt8((face.isItalic ? 1 : 0) | (face.isMonospaced ? 2 : 0)))
                writer.write(face.manufacturer)
                writer.write(face.version)
                writer.write(face.weightAxis?.minimum)
                writer.write(face.weightAxis?.maximum)
                writer.write(face.weightAxis?.defaultValue)
                writer.write(UInt8(face.width))
                writer.write(UInt32(face.axes.count))
                for axis in face.axes {
                    writer.write(axis.tag)
                    writer.write(axis.name)
                    writer.write(axis.value)
                }
            }
        }
        return writer.data
    }

    /// nil when the data isn't a cache this version understands.
    static func decode(_ data: Data) -> [String: CachedFile]? {
        data.withUnsafeBytes { buffer -> [String: CachedFile]? in
            var reader = ByteReader(buffer: buffer)
            do {
                guard try reader.u32() == magic, try reader.u32() == version else { return nil }
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
                    for _ in 0..<faceCount {
                        let index = Int(try reader.u32())
                        let postScriptName = try reader.string()
                        let familyName = try reader.string()
                        let styleName = try reader.string()
                        let fullName = try reader.string()
                        let weight = Int(try reader.u32())
                        let familyClass = Int(try reader.u8())
                        let flags = try reader.u8()
                        let manufacturer = try reader.optionalString()
                        let version = try reader.optionalString()
                        let minimum = try reader.optionalDouble()
                        let maximum = try reader.optionalDouble()
                        let defaultValue = try reader.optionalDouble()
                        let width = Int(try reader.u8())
                        let axisCount = Int(try reader.u32())
                        var axes: [VariationAxis] = []
                        for _ in 0..<axisCount {
                            axes.append(VariationAxis(tag: try reader.string(), name: try reader.string(), value: try reader.double()))
                        }
                        var axis: WeightAxis?
                        if let minimum, let maximum, let defaultValue {
                            axis = WeightAxis(minimum: minimum, maximum: maximum, defaultValue: defaultValue)
                        }
                        faces.append(FontFace(
                            id: FaceID(path: path, index: index), postScriptName: postScriptName, familyName: familyName,
                            styleName: styleName, fullName: fullName, weight: weight, isItalic: flags & 1 != 0,
                            isMonospaced: flags & 2 != 0, familyClass: familyClass, manufacturer: manufacturer,
                            version: version, weightAxis: axis, width: width, axes: axes
                        ))
                    }
                    files[path] = CachedFile(stamp: stamp, dateAdded: dateAdded, faces: faces)
                }
                return files
            } catch {
                return nil
            }
        }
    }
}

private struct ByteWriter {
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
}

private struct ByteReader {
    struct Truncated: Error {}

    let buffer: UnsafeRawBufferPointer
    var offset = 0

    init(buffer: UnsafeRawBufferPointer) {
        self.buffer = buffer
    }

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
}
