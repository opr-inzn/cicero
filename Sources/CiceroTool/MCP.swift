import ArgumentParser
import CiceroCommands
import Foundation
import MCP
import System

struct MCPServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Answer AI agents as an MCP server, on standard input and output.",
        discussion: """
            Agent apps start it, like Claude Code, Claude Desktop and Codex; see the help page for how to add it. Each \
            command is a tool with the command's options as inputs, and answers in the JSON --json prints.
            """
    )

    @Flag(help: "Only the tools that find and check, none that change things.")
    var readOnly = false

    func run() async throws {
        // Standard output is the agent's: only the server writes there.
        let output = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        let tools = MCPTools.all(readOnly: readOnly)
        let server = Server(
            name: "cicero",
            version: Version.text,
            title: "Cicero",
            instructions: MCPTools.instructions,
            capabilities: .init(resources: .init(subscribe: false, listChanged: false), tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools.map(\.tool))
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard let tool = tools.first(where: { $0.tool.name == parameters.name }) else {
                return MCPTools.failure(CommandError(.invalidArgument, "There’s no tool named \(parameters.name)."))
            }
            return await MCPTools.call(tool, parameters.arguments ?? [:])
        }
        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: [MCPTools.coverageResource])
        }
        await server.withMethodHandler(ReadResource.self) { parameters in
            guard parameters.uri == MCPTools.coverageResource.uri else {
                throw MCPError.invalidParams("There’s no resource \(parameters.uri).")
            }
            return ReadResource.Result(contents: [.text(await MCPTools.coverageSets(), uri: parameters.uri, mimeType: "application/json")])
        }
        try await server.start(transport: StdioTransport(input: .standardInput, output: FileDescriptor(rawValue: output)))
        await server.waitUntilCompleted()
        // A change the agent app asked for just before it closed is finished, not stopped halfway.
        await MCPTools.finish()
    }
}

enum MCPTools {
    struct Entry: Sendable {
        var tool: Tool
        var words: [String]
        var inputs: [Input]
    }

    struct Input: Sendable {
        enum Kind: Sendable {
            case positional
            case option
            case flag(inverted: Bool)
        }

        var kind: Kind
        var property: String
        var option: String
        var repeating: Bool
        var required: Bool
        var integer: Bool
        var values: [String]?
        var help: String
    }

    static let instructions = """
        Cicero is the font manager on this Mac. These tools find, check and change the fonts in Cicero’s library, as \
        the cicero command does, and answer in the same JSON as its --json (described on Cicero’s help page “The \
        Cicero CLI”). Name families by the id that find and list give; capitals don’t matter, and a name that isn’t \
        right gets suggestions. Fonts Cicero’s settings hide (fonts that come with macOS, Adobe Fonts, proofing fonts) \
        are hidden here too; systemFonts, adobeFonts and proofingFonts show or hide them for one call. A change that \
        asks first answers with the code needsConfirmation and the question, and changes nothing: ask the user, then \
        call again with yes: true. To see fonts, not only read about them, use compare: it answers with a picture.
        """

    static let coverageResource = Resource(
        name: "coverage",
        uri: "cicero://coverage",
        title: "Coverage sets",
        description: "The coverage sets Cicero checks fonts against, with the ids that coverage and find take as set.",
        mimeType: "application/json"
    )

    // Without compare's --png, with which a tool marked as only reading could write over any file: an agent can be told to by text in a font file, like its license.
    static let notForAgents: Set<String> = ["help", "version", "json", "debug", "png"]

    static let largestPicture = (side: 8000, bytes: 3_750_000)

    static func all(readOnly: Bool) -> [Entry] {
        var entries: [Entry] = []
        func walk(_ type: any ParsableCommand.Type, words: [String]) {
            let subcommands = type.configuration.subcommands
            if subcommands.isEmpty, let command = type as? any Answering.Type {
                if !readOnly || command.effect == .reads { entries.append(entry(command, words: words)) }
            }
            for subcommand in subcommands {
                walk(subcommand, words: words + [subcommand._commandName])
            }
        }
        walk(Cicero.self, words: [])
        return entries
    }

    private static func entry(_ command: any Answering.Type, words: [String]) -> Entry {
        let help = try! JSONDecoder().decode(HelpDump.self, from: Data(command._dumpHelp().utf8)).command
        let arguments = (help.arguments ?? []).filter(\.shouldDisplay)
        // ArgumentParser lists a flag's `--no-` form as a flag of its own.
        let longNames = Set(arguments.compactMap { $0.preferredName?.kind == "long" ? $0.preferredName?.name : nil })
        let isChange = command is any Changing.Type
        var inputs: [Input] = []
        for argument in arguments {
            guard let name = argument.preferredName?.name ?? argument.valueName,
                  !(name.hasPrefix("no-") && longNames.contains(String(name.dropFirst(3)))),
                  isChange || name != "yes",
                  let input = input(argument, inverted: longNames.contains("no-" + name)) else { continue }
            precondition(!inputs.contains { $0.property == input.property }, "\(words): two inputs named \(input.property)")
            inputs.append(input)
        }
        var properties: [String: Value] = [:]
        for input in inputs {
            var item: [String: Value] = ["type": .string(input.integer ? "integer" : "string")]
            if let values = input.values { item["enum"] = .array(values.map(Value.string)) }
            var schema: [String: Value]
            switch input.kind {
            case .flag: schema = ["type": "boolean"]
            case .positional, .option: schema = input.repeating ? ["type": "array", "items": .object(item)] : item
            }
            schema["description"] = .string(described(input.help, inputs))
            properties[input.property] = .object(schema)
        }
        let required = inputs.filter(\.required).map { Value.string($0.property) }
        var description = [help.abstract, help.discussion].compactMap { $0 }.map { described($0, inputs) }.joined(separator: "\n\n")
        if isChange {
            description += "\n\nA change that asks first answers with the code needsConfirmation and the question, and changes nothing: ask the user, then call again with yes: true."
        }
        let effect = command.effect
        let tool = Tool(
            name: words.joined(separator: "_"),
            description: description,
            inputSchema: ["type": "object", "properties": .object(properties), "required": .array(required), "additionalProperties": false],
            annotations: Tool.Annotations(
                readOnlyHint: effect == .reads,
                destructiveHint: effect == .reads ? nil : effect == .removes || effect == .replaces,
                idempotentHint: effect == .reads ? nil : effect == .adds || effect == .removes,
                openWorldHint: false
            )
        )
        return Entry(tool: tool, words: words, inputs: inputs)
    }

    private static func input(_ argument: HelpDump.Argument, inverted: Bool) -> Input? {
        var help = argument.abstract ?? ""
        if let value = argument.defaultValue { help += " Without it: \(value)." }
        if inverted { help += " true shows them, false hides them." }
        switch argument.kind {
        case .positional:
            guard let name = argument.valueName else { return nil }
            return Input(kind: .positional, property: camelCase(name), option: name, repeating: argument.isRepeating,
                         required: !argument.isOptional && !argument.isRepeating, integer: false, values: argument.allValues, help: help)
        case .option, .flag:
            guard let name = argument.preferredName?.name, argument.preferredName?.kind == "long", !notForAgents.contains(name) else {
                return nil
            }
            let kind: Input.Kind = argument.kind == .flag ? .flag(inverted: inverted) : .option
            let integer = argument.kind == .option && (argument.defaultValue.flatMap(Int.init) != nil || argument.valueName == "n")
            return Input(kind: kind, property: camelCase(name), option: name, repeating: argument.isRepeating,
                         required: argument.kind == .option && !argument.isOptional, integer: integer, values: argument.allValues, help: help)
        }
    }

    static func camelCase(_ name: String) -> String {
        let parts = name.split(separator: "-")
        return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }
            .joined()
    }

    private static func described(_ text: String, _ inputs: [Input]) -> String {
        var text = text
        for input in inputs where input.kind.isOption {
            text = text.replacingOccurrences(of: "--" + input.option, with: input.property)
        }
        return text
    }

    static func commandLine(_ entry: Entry, _ arguments: [String: Value]) throws -> [String] {
        let known = Set(entry.inputs.map(\.property))
        if let unknown = arguments.keys.sorted().first(where: { !known.contains($0) }) {
            throw CommandError(.invalidArgument, "\(entry.tool.name) has no input named \(unknown). It has: \(entry.inputs.map(\.property).joined(separator: ", ")).")
        }
        var options: [String] = []
        var positionals: [String] = []
        for input in entry.inputs {
            guard let value = arguments[input.property], value != .null else { continue }
            switch input.kind {
            case .flag(let inverted):
                guard case .bool(let on) = value else { throw invalid(input, "true or false") }
                if on { options.append("--" + input.option) } else if inverted { options.append("--no-" + input.option) }
            case .option:
                for word in try words(value, input) { options.append("--\(input.option)=\(word)") }
            case .positional:
                positionals += try words(value, input)
            }
        }
        // The arguments after --, so no name an agent gives, like --yes, is read as an option.
        return entry.words + options + ["--"] + positionals
    }

    private static func words(_ value: Value, _ input: Input) throws -> [String] {
        func word(_ value: Value) throws -> String {
            switch value {
            case .string(let text): return text
            case .int(let number): return String(number)
            case .double(let number) where number == number.rounded() && abs(number) < 1e15: return String(Int(number))
            default: throw invalid(input, input.integer ? "a whole number" : "text")
            }
        }
        if case .array(let values) = value {
            guard input.repeating else { throw invalid(input, input.integer ? "a whole number" : "text, not a list") }
            return try values.map(word)
        }
        return [try word(value)]
    }

    private static func invalid(_ input: Input, _ expected: String) -> CommandError {
        CommandError(.invalidArgument, "\(input.property) must be \(expected).")
    }

    @MainActor private static var last: Task<CallTool.Result, Never>?

    @MainActor
    static func call(_ entry: Entry, _ arguments: [String: Value]) async -> CallTool.Result {
        let previous = last
        let task = Task { @MainActor in
            _ = await previous?.value
            return await run(entry, arguments)
        }
        last = task
        return await task.value
    }

    @MainActor
    static func finish() async {
        _ = await last?.value
    }

    @MainActor
    private static func run(_ entry: Entry, _ arguments: [String: Value]) async -> CallTool.Result {
        do {
            let answer = try await result(of: try commandLine(entry, arguments))
            var content: [Tool.Content] = [.text(text: answer.compactText(), annotations: nil, _meta: nil)]
            if entry.words == ["compare"] { content += picture(answer) }
            return CallTool.Result(content: content, isError: false)
        } catch let error as CommandError {
            return failure(error)
        } catch {
            return failure(CommandError(.failed, error.localizedDescription))
        }
    }

    @MainActor
    private static func result(of commandLine: [String]) async throws -> JSON {
        let command: ParsableCommand
        do {
            command = try Cicero.parseAsRoot(commandLine)
        } catch {
            throw CommandError(.invalidArgument, Cicero.message(for: error))
        }
        guard let command = command as? any Answering else { throw CommandError(.failed, "That command doesn’t answer agents.") }
        return try await command.result()
    }

    static func failure(_ error: CommandError) -> CallTool.Result {
        CallTool.Result(content: [.text(text: error.json.compactText(), annotations: nil, _meta: nil)], isError: true)
    }

    private static func picture(_ answer: JSON) -> [Tool.Content] {
        guard case .string(let path) = answer["png"], let data = FileManager.default.contents(atPath: path) else { return [] }
        let side = [answer["width"], answer["height"]].compactMap { if case .int(let value) = $0 { value } else { nil } }.max() ?? 0
        guard side <= largestPicture.side, data.count <= largestPicture.bytes else {
            let note = "The picture is too large to send here (\(side) pixels on its longest side, \(data.count / 1000) kB). It is at \(path). Compare fewer styles, or use a smaller size or width."
            return [.text(text: note, annotations: nil, _meta: nil)]
        }
        return [.image(data: data.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil)]
    }

    @MainActor
    static func coverageSets() async -> String {
        do {
            return try await result(of: ["list", "coverage"]).compactText()
        } catch let error as CommandError {
            return error.json.compactText()
        } catch {
            return CommandError(.failed, error.localizedDescription).json.compactText()
        }
    }
}

extension MCPTools.Input.Kind {
    var isOption: Bool {
        if case .positional = self { false } else { true }
    }
}

private struct HelpDump: Decodable {
    struct Command: Decodable {
        var abstract: String?
        var discussion: String?
        var arguments: [Argument]?
    }

    struct Argument: Decodable {
        enum Kind: String, Decodable { case positional, option, flag }
        struct Name: Decodable {
            var kind: String
            var name: String
        }

        var kind: Kind
        var shouldDisplay: Bool
        var isOptional: Bool
        var isRepeating: Bool
        var names: [Name]?
        var preferredName: Name?
        var valueName: String?
        var defaultValue: String?
        var allValues: [String]?
        var abstract: String?
    }

    var command: Command
}
