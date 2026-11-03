import ArgumentParser
import CiceroCommands
import Foundation

@main
struct Cicero: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cicero",
        abstract: "Find, check and change the fonts in Cicero’s library.",
        discussion: """
            Works while Cicero is closed too, and never opens it. Finding and checking read what Cicero saved. \
            Changes go through Cicero while it’s open, so you see them at once; while it’s closed, the command \
            makes them itself. Add --json for answers that scripts and agents read; their fields are in the help page.
            """,
        version: Version.text,
        subcommands: [Status.self, Find.self, CoverageCheck.self, Compare.self, List.self, Activate.self, Deactivate.self, Tag.self, Folder.self,
                      MCPServer.self]
    )

    /// ArgumentParser's own `main`, except when the command line is wrong (an unknown option, a missing name): that's
    /// `invalidArgument`, exit 1, answered in JSON with `--json`, as for every other error. ArgumentParser would answer
    /// in text and exit 64.
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var command: ParsableCommand
        do {
            command = try parseAsRoot(arguments)
        } catch {
            guard exitCode(for: error) == .validationFailure else { Self.exit(withError: error) }
            // `--json` before a `--`, after which every word is a name.
            if arguments.prefix(while: { $0 != "--" }).contains("--json") {
                print(CommandError(.invalidArgument, message(for: error)).json.text())
            } else {
                FileHandle.standardError.write(Data((fullMessage(for: error) + "\n").utf8))
            }
            Self.exit(withError: ExitCode(CommandError.Code.invalidArgument.exitCode))
        }
        do {
            if var command = command as? AsyncParsableCommand {
                try await command.run()
            } else {
                try command.run()
            }
        } catch {
            Self.exit(withError: error)
        }
    }
}

enum Version {
    /// The app's version, from the bundle the tool is in.
    static var text: String {
        let info = Bundle.main.executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let plist = info.flatMap { NSDictionary(contentsOf: $0) }
        return plist?["CFBundleShortVersionString"] as? String ?? "development"
    }
}

/// The options every command takes.
struct CommonOptions: ParsableArguments {
    @Flag(help: "Answer in JSON, for scripts and agents.")
    var json = false

    @Flag(help: "Answer yes to every question.")
    var yes = false

    @Flag(help: "Say what takes time, on standard error.")
    var debug = false
}

/// Fonts Cicero's settings hide or show, which one command shows or hides instead. They never change the settings.
struct ShownOptions: ParsableArguments {
    @Flag(inversion: .prefixedNo, help: "Show or hide the fonts that come with macOS. Without it, as in Cicero’s settings.")
    var systemFonts: Bool?

    @Flag(inversion: .prefixedNo, help: "Show or hide Adobe Fonts from Creative Cloud. Without it, as in Cicero’s settings.")
    var adobeFonts: Bool?

    @Flag(inversion: .prefixedNo, help: "Show or hide the fonts installed for proofing in Adobe apps. Without it, as in Cicero’s settings; otherwise the command scans first, which takes longer.")
    var proofingFonts: Bool?

    var shown: ShownFonts { ShownFonts(systemFonts: systemFonts, adobeFonts: adobeFonts, proofingFonts: proofingFonts) }
}

/// A command that answers in JSON, as `--json` prints it, and that `cicero mcp` offers as a tool (see `MCPTools`).
protocol Answering: AsyncParsableCommand {
    var common: CommonOptions { get }
    /// What the command does to Cicero's library, for the agent apps.
    static var effect: Effect { get }
    /// The answer. Never prints, and never asks: a change that asks first throws `needsConfirmation` without `--yes`.
    func result() async throws -> JSON
}

/// What a command does to Cicero's library.
enum Effect {
    /// It only reads. (`compare` writes its picture, nothing else.)
    case reads
    /// It changes things, and adds or turns on; doing it again changes nothing more.
    case adds
    /// It renames: doing it again finds no name.
    case renames
    /// It takes away or turns off.
    case removes
}

/// A command that changes things, with `WriteDispatcher`.
protocol Changing: Answering {
    var change: WriteCommand { get }
    /// The fonts this one command shows or hides.
    var shown: ShownFonts { get }
}

extension Changing {
    var shown: ShownFonts { ShownFonts() }

    func result() async throws -> JSON {
        try await WriteDispatcher.perform(WriteRequest(change, confirmed: common.yes, shown: shown), environment: .current())
    }

    func run() async throws {
        try await write(change, common, shown)
    }
}

/// Runs a command's work and prints its answer, or its error, as text or JSON. Exits with the error's code, or with the
/// answer's own `exitCode` (as `coverage` does when characters are missing).
func answer(_ common: CommonOptions, text: (JSON) -> String, exitCode: (JSON) -> Int32 = { _ in 0 },
            _ work: () async throws -> JSON) async throws {
    let start = ContinuousClock.now
    let result: JSON
    do {
        result = try await work()
        print(common.json ? result.text() : text(result))
        if common.debug { FileHandle.standardError.write(Data("Took \(ContinuousClock.now - start).\n".utf8)) }
    } catch let error as CommandError {
        if common.json {
            print(error.json.text())
        } else {
            var message = "cicero: \(error.message)"
            if !error.suggestions.isEmpty {
                message += "\n" + (error.code == .notFound ? "Did you mean:" : "It can be:") + "\n"
                    + error.suggestions.map { "  \($0)" }.joined(separator: "\n")
            }
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        throw ExitCode(error.code.exitCode)
    }
    let code = exitCode(result)
    if code != 0 { throw ExitCode(code) }
}

/// With `rescan`, Cicero scans first while it's open; while it's closed, the command does, holding the lock (see
/// `WriteDispatcher`). When neither can (an old Cicero, or one not answering), the command scans and saves nothing.
func load(_ common: CommonOptions, _ shown: ShownOptions, rescan: Bool = false) async throws -> LibraryContext {
    let start = ContinuousClock.now
    let environment = ToolEnvironment.current()
    var scansHere = false
    if rescan {
        do {
            _ = try await WriteDispatcher.perform(WriteRequest(.rescan), environment: environment)
        } catch let error as CommandError where error.code != .unreadableUserData {
            scansHere = true
        }
    }
    let context = try await LibraryContext.load(environment, rescan: scansHere, shown: shown.shown, savesScan: false)
    if common.debug {
        FileHandle.standardError.write(Data("Read the library (\(context.library.families.count) families) in \(ContinuousClock.now - start).\n".utf8))
    }
    return context
}

struct Status: Answering {
    static let configuration = CommandConfiguration(
        abstract: "The library, or one family.",
        discussion: """
            Without a family: how many families and styles, when the library was last scanned, the locations, and \
            problems. With a family: the family and its styles, short. --style adds one style's details, --all-styles \
            every style's.
            """
    )

    @Argument(help: "A family’s name.", completion: .families)
    var family: String?

    @Option(help: ArgumentHelp("One style’s details: its name or PostScript name.", valueName: "style"), completion: .names(.styles))
    var style: String?

    @Flag(help: "Every style’s details.")
    var allStyles = false

    @Flag(help: "Scan the font folders first: Cicero does, while it’s open.")
    var rescan = false

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions

    @OptionGroup var common: CommonOptions

    static let effect = Effect.reads

    func result() async throws -> JSON {
        let context = try await load(common, hidden, rescan: rescan)
        guard let family else {
            if style != nil || allStyles { throw CommandError(.invalidArgument, "--style and --all-styles go with a family.") }
            return StatusCommand.library(in: context)
        }
        return try StatusCommand.family(family, style: style, allStyles: allStyles, in: context)
    }

    func run() async throws {
        try await answer(common, text: Text.status, result)
    }
}

/// The options of `find` and `list families`.
struct FindArguments: ParsableArguments {
    @Option(help: "Families of this foundry.", completion: .names(.foundries))
    var foundry: String?

    @Option(name: .customLong("class"), help: "Families of this classification.", completion: .names(.classes))
    var classification: String?

    @Option(help: ArgumentHelp("Released in a year, or between years: 2019, 2015..2020, 2015.., ..2020.", valueName: "years"))
    var released: String?

    @Option(help: ArgumentHelp("Added on a date, or between dates: 2024, 2024-03, 2024-03-15, 2024-03.., ..2024.", valueName: "dates"))
    var added: String?

    @Option(help: "Families whose regular style has every character of this text.")
    var text: String?

    @Option(help: ArgumentHelp("Families whose regular style has every character of this coverage set (see cicero list coverage).", valueName: "id"), completion: .names(.coverage))
    var set: String?

    @Option(help: ArgumentHelp("With --text or --set: families may lack up to this many characters.", valueName: "n"))
    var missing: Int?

    @Option(help: "Families with this tag.", completion: .tags)
    var tag: String?

    @Option(help: "Families in this folder.", completion: .folders)
    var folder: String?

    @Option(help: "Families in this location: its name or path.", completion: .names(.locations))
    var location: String?

    @Flag(help: "Families with a style on.")
    var active = false

    @Flag(help: "Families with a style off.")
    var inactive = false

    @Option(help: ArgumentHelp("name (A to Z), added or released (latest first).", valueName: "order"))
    var sort: FindOptions.Sort?

    @Option(name: .customLong("filter"), help: ArgumentHelp(
        "Families with a style that is this: italic, bold or another weight (thin … black, or 100 … 900), condensed, extended, variable, tnum, onum. Give it more than once for more.",
        valueName: "word"), completion: .styleWords)
    var filters: [String] = []

    @Option(help: "How many families to show; 0 for all.")
    var limit = 50

    @Option(help: "How many families to skip.")
    var offset = 0

    func options(words: [String]) -> FindOptions {
        var options = FindOptions()
        options.words = words
        options.foundry = foundry
        options.classification = classification
        options.released = released
        options.added = added
        options.text = text
        options.set = set
        options.missing = missing
        options.tag = tag
        options.folder = folder
        options.location = location
        options.active = active
        options.inactive = inactive
        options.sort = sort
        options.filters = filters
        options.limit = limit
        options.offset = offset
        return options
    }
}

extension FindOptions.Sort: ExpressibleByArgument {}

struct Find: Answering {
    static let configuration = CommandConfiguration(
        abstract: "Find families.",
        discussion: """
            Words are looked for as Cicero’s search field looks for them: in names, foundries, designers, classes, tags \
            and notes. Unlike the search field, also in the fonts’ licenses, descriptions, and license, manufacturer \
            and designer URLs, read from the font files, which takes longer.
            """
    )

    @Argument(help: "Words to look for. A family needs all of them, unless --any.")
    var words: [String] = []

    @Flag(help: "Families with any of the words, not all of them, like trial, unlicensed or test. Words with spaces between them in one argument (in quotes in Terminal) are one search: all of them must be found.")
    var any = false

    @OptionGroup var find: FindArguments
    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.reads

    func result() async throws -> JSON {
        var options = find.options(words: words)
        options.any = any
        return try FindCommand.run(options, in: try await load(common, hidden))
    }

    func run() async throws {
        try await answer(common, text: Text.families, result)
    }
}

struct CoverageCheck: Answering {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "Whether a family has every character of a set or a text, and which it lacks.",
        discussion: "Cicero checks each family’s regular style."
    )

    @Argument(help: "A family’s name.", completion: .families)
    var family: String

    @Option(help: ArgumentHelp("A coverage set (see cicero list coverage).", valueName: "id"), completion: .names(.coverage))
    var set: String?

    @Option(help: "Some text.")
    var text: String?

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.reads

    func result() async throws -> JSON {
        try await CoverageCommand.run(family: family, set: set, text: text, in: try await load(common, hidden))
    }

    func run() async throws {
        // 3 when characters are missing, as `diff` exits 1 when files differ: a script can ask without reading the JSON.
        try await answer(common, text: Text.coverageCheck, exitCode: { Text.bool($0["covered"]) == false ? 3 : 0 }, result)
    }
}

struct Compare: Answering {
    static let configuration = CommandConfiguration(
        abstract: "Draw families or styles in one picture, the same text in each, to look at them side by side.",
        discussion: """
            Writes a PNG: each family’s regular style, or every style with --all-styles, under a label with its name. A \
            name that isn’t a family’s can be a style’s PostScript name (Inter-Bold) or full name (Inter Bold). Fonts are \
            drawn from their files, on or off. A character a font lacks is drawn as the font’s own .notdef glyph, never in another font, \
            and the label says which characters it lacks. Without --png, the picture goes in the temporary folder; the \
            answer says where.
            """
    )

    @Argument(help: "Families’ names, or styles’ PostScript or full names.", completion: .families)
    var names: [String] = []

    @Flag(help: "Every style of the families, not only the regular one.")
    var allStyles = false

    @Option(help: "The text to draw. Without it: “\(CompareCommand.defaultText)”")
    var text: String?

    @Option(help: ArgumentHelp("The letters’ size in pixels (\(CompareCommand.sizes.lowerBound)–\(CompareCommand.sizes.upperBound)).", valueName: "pixels"))
    var size = 48

    @Option(help: ArgumentHelp("The picture’s width in pixels (\(CompareCommand.widths.lowerBound)–\(CompareCommand.widths.upperBound)). The text wraps to it.", valueName: "pixels"))
    var width = 1200

    @Option(help: ArgumentHelp("Where to write the picture.", valueName: "file"), completion: .file(extensions: ["png"]))
    var png: String?

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.reads

    func result() async throws -> JSON {
        var options = CompareCommand.Options()
        options.names = names
        options.allStyles = allStyles
        options.text = text
        options.size = size
        options.width = width
        options.png = png
        return try CompareCommand.run(options, in: try await load(common, hidden))
    }

    func run() async throws {
        try await answer(common, text: Text.compare, result)
    }
}

extension ListCommand.What: ExpressibleByArgument {}

struct List: Answering {
    static let configuration = CommandConfiguration(
        abstract: "List families, tags, folders, locations, foundries or coverage sets."
    )

    @Argument(help: ArgumentHelp("families, tags, folders, locations, foundries or coverage.", valueName: "what"))
    var what: ListCommand.What

    @Option(help: "How many families to show; 0 for all.")
    var limit = 50

    @Option(help: "How many families to skip.")
    var offset = 0

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.reads

    func result() async throws -> JSON {
        var options = FindOptions()
        options.limit = limit
        options.offset = offset
        return try ListCommand.run(what, options: options, in: try await load(common, hidden))
    }

    func run() async throws {
        try await answer(common, text: { Text.list(what, $0) }, result)
    }
}

// MARK: Changes

/// Makes a change and prints what it did. A change that asks first asks in the terminal (y/N), unless --yes answers
/// it; without a terminal, or with --json, it stops with `needsConfirmation` and the question.
func write(_ command: WriteCommand, _ common: CommonOptions, _ shown: ShownFonts = ShownFonts()) async throws {
    try await answer(common, text: { Text.changes(command, $0) }) {
        var request = WriteRequest(command, confirmed: common.yes, shown: shown)
        while true {
            do {
                return try await WriteDispatcher.perform(request, environment: .current())
            } catch let error as CommandError where error.code == .needsConfirmation && !request.confirmed && !common.json
                && isatty(STDIN_FILENO) == 1 && isatty(STDERR_FILENO) == 1 {
                let question = error.question.map { "\($0.title)\n\($0.message)\n" } ?? error.message + "\n"
                FileHandle.standardError.write(Data((question + "Go on? [y/N] ").utf8))
                guard let reply = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), ["y", "yes"].contains(reply) else {
                    throw CommandError(.needsConfirmation, "Nothing changed.")
                }
                request.confirmed = true
            }
        }
    }
}

struct Activate: Changing {
    static let configuration = CommandConfiguration(
        abstract: "Turn on families, a folder’s fonts or a tag’s families.",
        discussion: "Fonts go on where they are, as when you turn them on in Cicero.",
        aliases: ["on"]
    )

    @Argument(help: "Families’ names.", completion: .families)
    var families: [String] = []

    @Option(help: "Every font in this folder.", completion: .folders)
    var folder: String?

    @Option(help: "Every family with this tag.", completion: .tags)
    var tag: String?

    @Flag(help: "Until Cicero quits. Only while Cicero is open.")
    var untilQuit = false

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.adds
    var change: WriteCommand { .activate(families: families, folder: folder, tag: tag, untilQuit: untilQuit) }
    var shown: ShownFonts { hidden.shown }
}

struct Deactivate: Changing {
    static let configuration = CommandConfiguration(
        abstract: "Turn off families, a folder’s fonts or a tag’s families.",
        aliases: ["off"]
    )

    @Argument(help: "Families’ names.", completion: .families)
    var families: [String] = []

    @Option(help: "Every font in this folder.", completion: .folders)
    var folder: String?

    @Option(help: "Every family with this tag.", completion: .tags)
    var tag: String?

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    static let effect = Effect.removes
    var change: WriteCommand { .deactivate(families: families, folder: folder, tag: tag) }
    var shown: ShownFonts { hidden.shown }
}

struct Tag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make, rename or delete a tag, or give one to families or take it off them.",
        subcommands: [Create.self, Add.self, Remove.self, Rename.self, Delete.self]
    )

    struct Create: Changing {
        static let configuration = CommandConfiguration(abstract: "Make a tag. Nothing changes when there’s one of that name.")

        @Argument(help: "The tag’s name.")
        var name: String

        @Option(help: ArgumentHelp("red, orange, yellow, green, blue, purple, gray or sand. Without it, the first colour no tag has.", valueName: "colour"), completion: .colors)
        var color: String?

        @OptionGroup var common: CommonOptions

        static let effect = Effect.adds
        var change: WriteCommand { .tagCreate(name: name, color: color) }
    }

    struct Add: Changing {
        static let configuration = CommandConfiguration(abstract: "Give families a tag.")

        @Argument(help: "The tag.", completion: .tags)
        var tag: String

        @Argument(help: "Families’ names.", completion: .families)
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        static let effect = Effect.adds
        var change: WriteCommand { .tagAdd(tag: tag, families: families) }
        var shown: ShownFonts { hidden.shown }
    }

    struct Remove: Changing {
        static let configuration = CommandConfiguration(abstract: "Take a tag off families.")

        @Argument(help: "The tag.", completion: .tags)
        var tag: String

        @Argument(help: "Families’ names.", completion: .families)
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        static let effect = Effect.removes
        var change: WriteCommand { .tagRemove(tag: tag, families: families) }
        var shown: ShownFonts { hidden.shown }
    }

    struct Rename: Changing {
        static let configuration = CommandConfiguration(
            abstract: "Rename a tag.",
            discussion: "The families that have it keep it, under the new name, and so do smart folders’ rules."
        )

        @Argument(help: "The tag.", completion: .tags)
        var tag: String

        @Argument(help: "Its new name.")
        var name: String

        @OptionGroup var common: CommonOptions

        static let effect = Effect.renames
        var change: WriteCommand { .tagRename(tag: tag, name: name) }
    }

    struct Delete: Changing {
        static let configuration = CommandConfiguration(
            abstract: "Delete tags.",
            discussion: "Takes them off every family and out of smart folders’ rules, as Delete Tag in Cicero does. The fonts stay."
        )

        @Argument(help: "The tags.", completion: .tags)
        var tags: [String] = []

        @OptionGroup var common: CommonOptions

        static let effect = Effect.removes
        var change: WriteCommand { .tagDelete(tags: tags) }
    }
}

struct Folder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make, rename or delete a folder, or put families in one or take them out.",
        subcommands: [Create.self, Add.self, Remove.self, Rename.self, Delete.self]
    )

    struct Create: Changing {
        static let configuration = CommandConfiguration(abstract: "Make a folder. Nothing changes when there’s one of that name.")

        @Argument(help: "The folder’s name.")
        var name: String

        @OptionGroup var common: CommonOptions

        static let effect = Effect.adds
        var change: WriteCommand { .folderCreate(name: name) }
    }

    struct Add: Changing {
        static let configuration = CommandConfiguration(abstract: "Put families in a folder, every style of them.")

        @Argument(help: "The folder: its name or id.", completion: .folders)
        var folder: String

        @Argument(help: "Families’ names.", completion: .families)
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        static let effect = Effect.adds
        var change: WriteCommand { .folderAdd(folder: folder, families: families) }
        var shown: ShownFonts { hidden.shown }
    }

    struct Remove: Changing {
        static let configuration = CommandConfiguration(abstract: "Take families out of a folder.")

        @Argument(help: "The folder: its name or id.", completion: .folders)
        var folder: String

        @Argument(help: "Families’ names.", completion: .families)
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        static let effect = Effect.removes
        var change: WriteCommand { .folderRemove(folder: folder, families: families) }
        var shown: ShownFonts { hidden.shown }
    }

    struct Rename: Changing {
        static let configuration = CommandConfiguration(abstract: "Rename a folder. Its fonts stay in it.")

        @Argument(help: "The folder: its name or id.", completion: .folders)
        var folder: String

        @Argument(help: "Its new name.")
        var name: String

        @OptionGroup var common: CommonOptions

        static let effect = Effect.renames
        var change: WriteCommand { .folderRename(folder: folder, name: name) }
    }

    struct Delete: Changing {
        static let configuration = CommandConfiguration(
            abstract: "Delete folders.",
            discussion: "As Delete Folder in Cicero: the fonts stay in the library, and stay on or off as they are."
        )

        @Argument(help: "The folders: their names or ids.", completion: .folders)
        var folders: [String] = []

        @OptionGroup var common: CommonOptions

        static let effect = Effect.removes
        var change: WriteCommand { .folderDelete(folders: folders) }
    }
}
