import Foundation

/// A JSON value whose objects keep their fields in order, so every answer has `schema` first and its fields where the
/// contract puts them. A field without a value is left out (see `JSONObject`), never written as null.
public enum JSON: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSON])
    case object(JSONObject)

    /// Indented by two spaces, a field per line, as `--json` prints it; `/` isn't escaped, other characters are written
    /// as they are.
    public func text(indent: String = "") -> String {
        switch self {
        case .string(let value): return Self.quoted(value)
        case .int(let value): return String(value)
        case .double(let value):
            if value.isFinite, value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
            return value.isFinite ? String(value) : "0"
        case .bool(let value): return value ? "true" : "false"
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let inner = indent + "  "
            return "[\n" + values.map { inner + $0.text(indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let object):
            guard !object.fields.isEmpty else { return "{}" }
            let inner = indent + "  "
            return "{\n" + object.fields.map { inner + Self.quoted($0.key) + ": " + $0.value.text(indent: inner) }.joined(separator: ",\n")
                + "\n" + indent + "}"
        }
    }

    static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let scalar where scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || scalar.value == 0x2028 || scalar.value == 0x2029:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// A field's value as JSON, for tests and the MCP server to read back.
    public subscript(key: String) -> JSON? {
        if case .object(let object) = self { return object.fields.first { $0.key == key }?.value }
        return nil
    }
}

/// An object's fields in the order they were set. Setting nil leaves the field out.
public struct JSONObject: Equatable, Sendable {
    public private(set) var fields: [(key: String, value: JSON)] = []

    public init() {}

    public static func == (a: JSONObject, b: JSONObject) -> Bool {
        a.fields.count == b.fields.count && zip(a.fields, b.fields).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public subscript(key: String) -> JSON? {
        get { fields.first { $0.key == key }?.value }
        set {
            if let index = fields.firstIndex(where: { $0.key == key }) {
                if let newValue { fields[index].value = newValue } else { fields.remove(at: index) }
            } else if let newValue {
                fields.append((key, newValue))
            }
        }
    }

    public mutating func set(_ key: String, _ value: String?) { self[key] = value.map(JSON.string) }
    public mutating func set(_ key: String, _ value: Int?) { self[key] = value.map(JSON.int) }
    public mutating func set(_ key: String, _ value: Double?) { self[key] = value.map(JSON.double) }
    public mutating func set(_ key: String, _ value: Bool?) { self[key] = value.map(JSON.bool) }
    public mutating func set(_ key: String, _ value: Date?) { self[key] = value.map { .string(JSONDates.text($0)) } }
    /// A list is written also when it's empty.
    public mutating func set(_ key: String, _ values: [String]) { self[key] = .array(values.map(JSON.string)) }
    public mutating func set(_ key: String, _ values: [JSON]) { self[key] = .array(values) }
    public mutating func set(_ key: String, _ object: JSONObject?) { self[key] = object.map(JSON.object) }

    /// An answer: `"schema": 1` first.
    public static func answer() -> JSONObject {
        var object = JSONObject()
        object.set("schema", Contract.schema)
        return object
    }

    public var json: JSON { .object(self) }
}

/// ISO 8601 in UTC, to the second: "2025-04-02T09:14:00Z".
enum JSONDates {
    static func text(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }
}

/// The JSON contract's version: renaming, removing or retyping a field raises it; new fields and new values of a field
/// with a list of values don't.
public enum Contract {
    public static let schema = 1
}
