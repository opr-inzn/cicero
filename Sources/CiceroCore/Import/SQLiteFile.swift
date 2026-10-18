import Foundation
import SQLite3

/// A SQLite database opened read-only, for reading another app's library. Opened as immutable, so SQLite never writes
/// to it or looks for a journal; open a copy of a file another app may be writing to.
final class SQLiteFile {
    enum Failure: Error, Equatable {
        case unreadable
        case query(String)
    }

    /// One row, column name → value: Int64, Double, String, Data, or missing for NULL.
    typealias Row = [String: Any]

    private var handle: OpaquePointer?

    init(_ url: URL) throws {
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string,
              sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else {
            sqlite3_close(handle)
            throw Failure.unreadable
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    /// The table's columns, empty when there's no such table.
    func columns(of table: String) -> Set<String> {
        let rows = (try? self.rows("PRAGMA table_info(\(table))")) ?? []
        return Set(rows.compactMap { $0["name"] as? String })
    }

    /// Every row the statement gives.
    func rows(_ sql: String) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.query(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw Failure.query(String(cString: sqlite3_errmsg(handle))) }
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = sqlite3_column_text(statement, column).map { String(cString: $0) }
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    row[name] = sqlite3_column_blob(statement, column).map { Data(bytes: $0, count: count) } ?? Data()
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }
}

extension Dictionary where Key == String, Value == Any {
    /// A column as a whole number: an integer, a real, or text that is one; 0 when missing.
    func int(_ column: String) -> Int {
        switch self[column] {
        case let value as Int64: Int(value)
        case let value as Double where value.isFinite: Int(value)
        case let value as String: Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
        default: 0
        }
    }

    /// A column as a real number, for dates stored as seconds; 0 when missing.
    func double(_ column: String) -> Double {
        switch self[column] {
        case let value as Int64: Double(value)
        case let value as Double: value
        case let value as String: Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
        default: 0
        }
    }

    /// A column as text, trimmed; nil when missing or empty.
    func text(_ column: String) -> String? {
        let text: String? = switch self[column] {
        case let value as String: value
        case let value as Int64: String(value)
        default: nil
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
