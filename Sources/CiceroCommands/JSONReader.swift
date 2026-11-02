import Foundation

extension JSON {
    /// Reads JSON text back into a value whose objects keep their fields in order: Cicero's reply to a request (see
    /// `Requests`), which the command prints as it is. Numbers without a fraction or an exponent are `int`s; `null` is
    /// left out of objects and arrays, as the contract has no nulls. Nil when the text isn't JSON.
    public init?(text: String) {
        var reader = Reader(scalars: Array(text.unicodeScalars))
        guard let value = reader.value(), reader.atEnd else { return nil }
        self = value
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        var atEnd: Bool {
            mutating get {
                skipSpace()
                return index == scalars.count
            }
        }

        mutating func skipSpace() {
            while index < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 }
        }

        mutating func value() -> JSON? {
            skipSpace()
            guard index < scalars.count else { return nil }
            switch scalars[index] {
            case "{": return object()
            case "[": return array()
            case "\"": return string().map(JSON.string)
            case "t": return word("true") ? .bool(true) : nil
            case "f": return word("false") ? .bool(false) : nil
            default: return number()
            }
        }

        mutating func word(_ word: String) -> Bool {
            let letters = Array(word.unicodeScalars)
            guard index + letters.count <= scalars.count, Array(scalars[index..<index + letters.count]) == letters else { return false }
            index += letters.count
            return true
        }

        /// A null, which an object or array leaves out.
        mutating func null() -> Bool {
            skipSpace()
            return word("null")
        }

        mutating func object() -> JSON? {
            index += 1
            var object = JSONObject()
            skipSpace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return .object(object)
            }
            while true {
                skipSpace()
                guard let key = string() else { return nil }
                skipSpace()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                if !null() {
                    guard let value = value() else { return nil }
                    object[key] = value
                }
                skipSpace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "}" { index += 1; return .object(object) }
                return nil
            }
        }

        mutating func array() -> JSON? {
            index += 1
            var values: [JSON] = []
            skipSpace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return .array(values)
            }
            while true {
                if !null() {
                    guard let value = value() else { return nil }
                    values.append(value)
                }
                skipSpace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "]" { index += 1; return .array(values) }
                return nil
            }
        }

        mutating func string() -> String? {
            guard index < scalars.count, scalars[index] == "\"" else { return nil }
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"": return String(out)
                case "\\":
                    guard index < scalars.count else { return nil }
                    let escaped = scalars[index]
                    index += 1
                    switch escaped {
                    case "\"", "\\", "/": out.append(escaped)
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "b": out.append("\u{8}")
                    case "f": out.append("\u{C}")
                    case "u":
                        guard var code = hex() else { return nil }
                        // A pair of surrogates is one character.
                        if (0xD800...0xDBFF).contains(code), word("\\u"), let low = hex(), (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + (code - 0xD800) << 10 + (low - 0xDC00)
                        }
                        guard let decoded = Unicode.Scalar(code) else { return nil }
                        out.append(decoded)
                    default: return nil
                    }
                default: out.append(scalar)
                }
            }
            return nil
        }

        mutating func hex() -> UInt32? {
            guard index + 4 <= scalars.count, let code = UInt32(String(String.UnicodeScalarView(scalars[index..<index + 4])), radix: 16) else { return nil }
            index += 4
            return code
        }

        mutating func number() -> JSON? {
            let start = index
            while index < scalars.count, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) { index += 1 }
            let text = String(String.UnicodeScalarView(scalars[start..<index]))
            if let int = Int(text) { return .int(int) }
            return Double(text).map(JSON.double)
        }
    }
}

extension CommandError {
    /// The error in an answer (`{ "schema": 1, "error": {…} }`), as Cicero replied it to a request; nil for an answer
    /// that isn't one.
    public init?(answer: JSON) {
        guard let error = answer["error"], case .string(let code)? = error["code"], let known = Code(rawValue: code) else { return nil }
        var message = ""
        if case .string(let text)? = error["message"] { message = text }
        var suggestions: [String] = []
        if case .array(let values)? = error["suggestions"] {
            suggestions = values.compactMap { if case .string(let text) = $0 { text } else { nil } }
        }
        var question: Question?
        if let asked = error["question"], case .string(let kind)? = asked["kind"], case .string(let title)? = asked["title"],
           case .string(let text)? = asked["message"] {
            question = Question(kind: kind, title: title, message: text)
        }
        self.init(known, message, suggestions: suggestions, question: question)
    }
}
