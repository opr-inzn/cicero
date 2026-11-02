import Foundation

/// Why a command stopped, with what the user or a script can do about it. Answered as
/// `{ "schema": 1, "error": { "code", "message", "suggestions", "question" } }`.
public struct CommandError: Error, Sendable {
    public enum Code: String, Sendable {
        /// No family, style, tag, folder, location or set of that name.
        case notFound
        /// The name fits more than one thing, like two folders with the same name.
        case ambiguous
        /// A change that asks first, without a terminal to ask in and without `--yes`.
        case needsConfirmation
        /// Cicero is open and didn't take the request in time, or does the work itself.
        case busy
        /// The command needs Cicero open.
        case appNotOpen
        /// Cicero's user-data.json can't be read.
        case unreadableUserData
        case invalidArgument
        case failed

        /// What the command exits with.
        public var exitCode: Int32 {
            switch self {
            case .notFound, .ambiguous: 2
            case .needsConfirmation: 4
            case .busy: 5
            case .appNotOpen, .unreadableUserData, .invalidArgument, .failed: 1
            }
        }
    }

    /// A question a change asks before it's made (see `ActivationQuestions`).
    public struct Question: Sendable {
        /// `manyFamilies`, `movingOutOfSharedFolder`.
        public var kind: String
        public var title: String
        public var message: String

        public init(kind: String, title: String, message: String) {
            self.kind = kind
            self.title = title
            self.message = message
        }
    }

    public var code: Code
    public var message: String
    /// Near names, for `notFound`; the things a name fits, for `ambiguous`.
    public var suggestions: [String]
    public var question: Question?

    public init(_ code: Code, _ message: String, suggestions: [String] = [], question: Question? = nil) {
        self.code = code
        self.message = message
        self.suggestions = suggestions
        self.question = question
    }

    public var json: JSON {
        var error = JSONObject()
        error.set("code", code.rawValue)
        error.set("message", message)
        if !suggestions.isEmpty || code == .notFound || code == .ambiguous { error.set("suggestions", suggestions) }
        if let question {
            var object = JSONObject()
            object.set("kind", question.kind)
            object.set("title", question.title)
            object.set("message", question.message)
            error.set("question", object)
        }
        var answer = JSONObject.answer()
        answer.set("error", error)
        return answer.json
    }

    static func invalid(_ message: String) -> CommandError { CommandError(.invalidArgument, message) }
}
