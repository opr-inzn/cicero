import Foundation

public struct CommandError: Error, Sendable {
    public enum Code: String, Sendable {
        case notFound
        case ambiguous
        case needsConfirmation
        case busy
        case appNotOpen
        case unreadableUserData
        case invalidArgument
        case failed

        public var exitCode: Int32 {
            switch self {
            case .notFound, .ambiguous: 2
            case .needsConfirmation: 4
            case .busy: 5
            case .appNotOpen, .unreadableUserData, .invalidArgument, .failed: 1
            }
        }
    }

    public struct Question: Sendable {
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
