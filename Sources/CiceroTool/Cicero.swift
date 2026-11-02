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
        subcommands: [Status.self, Find.self, CoverageCheck.self, List.self, Activate.self, Deactivate.self, Tag.self, Folder.self]
    )
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

/// Runs a command's work and prints its answer, or its error, as text or JSON. Exits with the error's code.
func answer(_ common: CommonOptions, text: (JSON) -> String, _ work: () async throws -> JSON) async throws {
    let start = ContinuousClock.now
    do {
        let result = try await work()
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
}

func load(_ common: CommonOptions, _ shown: ShownOptions, rescan: Bool = false) async throws -> LibraryContext {
    let start = ContinuousClock.now
    let context = try await LibraryContext.load(.current(), rescan: rescan, shown: shown.shown)
    if common.debug {
        FileHandle.standardError.write(Data("Read the library (\(context.library.families.count) families) in \(ContinuousClock.now - start).\n".utf8))
    }
    return context
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "The library, or one family.",
        discussion: """
            Without a family: how many families and styles, when the library was last scanned, the locations, and \
            problems. With a family: the family and its styles, short. --style adds one style's details, --all-styles \
            every style's.
            """
    )

    @Argument(help: "A family’s name.")
    var family: String?

    @Option(help: ArgumentHelp("One style’s details: its name or PostScript name.", valueName: "style"))
    var style: String?

    @Flag(help: "Every style’s details.")
    var allStyles = false

    @Flag(help: "Scan the font folders first. While Cicero is open, Cicero saves its own scans, so this scan isn’t saved.")
    var rescan = false

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions

    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.status) {
            let context = try await load(common, hidden, rescan: rescan)
            guard let family else {
                if style != nil || allStyles { throw CommandError(.invalidArgument, "--style and --all-styles go with a family.") }
                return StatusCommand.library(in: context)
            }
            return try StatusCommand.family(family, style: style, allStyles: allStyles, in: context)
        }
    }
}

/// The options of `find` and `list families`.
struct FindArguments: ParsableArguments {
    @Option(help: "Families of this foundry.")
    var foundry: String?

    @Option(name: .customLong("class"), help: "Families of this classification.")
    var classification: String?

    @Option(help: ArgumentHelp("Released in a year, or between years: 2019, 2015..2020, 2015.., ..2020.", valueName: "years"))
    var released: String?

    @Option(help: ArgumentHelp("Added on a date, or between dates: 2024, 2024-03, 2024-03-15, 2024-03.., ..2024.", valueName: "dates"))
    var added: String?

    @Option(help: "Families whose regular style has every character of this text.")
    var text: String?

    @Option(help: ArgumentHelp("Families whose regular style has every character of this coverage set (see cicero list coverage).", valueName: "id"))
    var set: String?

    @Option(help: ArgumentHelp("With --text or --set: families may lack up to this many characters.", valueName: "n"))
    var missing: Int?

    @Option(help: "Families with this tag.")
    var tag: String?

    @Option(help: "Families in this folder.")
    var folder: String?

    @Option(help: "Families in this location: its name or path.")
    var location: String?

    @Flag(help: "Families with a style on.")
    var active = false

    @Flag(help: "Families with a style off.")
    var inactive = false

    @Option(help: ArgumentHelp("name (A to Z), added or released (latest first).", valueName: "order"))
    var sort: FindOptions.Sort?

    @Option(name: .customLong("filter"), help: ArgumentHelp(
        "Families with a style that is this: italic, bold or another weight (thin … black, or 100 … 900), condensed, extended, variable, tnum, onum. Give it more than once for more.",
        valueName: "word"))
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

struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find families.",
        discussion: "Words are looked for as Cicero’s search field looks for them: in names, foundries, designers, classes, tags and notes."
    )

    @Argument(help: "Words to look for.")
    var words: [String] = []

    @OptionGroup var find: FindArguments
    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.families) {
            try FindCommand.run(find.options(words: words), in: try await load(common, hidden))
        }
    }
}

struct CoverageCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "Whether a family has every character of a set or a text, and which it lacks.",
        discussion: "Cicero checks each family’s regular style."
    )

    @Argument(help: "A family’s name.")
    var family: String

    @Option(help: ArgumentHelp("A coverage set (see cicero list coverage).", valueName: "id"))
    var set: String?

    @Option(help: "Some text.")
    var text: String?

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.coverageCheck) {
            try await CoverageCommand.run(family: family, set: set, text: text, in: try await load(common, hidden))
        }
    }
}

extension ListCommand.What: ExpressibleByArgument {}

struct List: AsyncParsableCommand {
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

    func run() async throws {
        try await answer(common, text: { Text.list(what, $0) }) {
            var options = FindOptions()
            options.limit = limit
            options.offset = offset
            return try ListCommand.run(what, options: options, in: try await load(common, hidden))
        }
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

struct Activate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Turn on families, a folder’s fonts or a tag’s families.",
        discussion: "Fonts go on where they are, as when you turn them on in Cicero.",
        aliases: ["on"]
    )

    @Argument(help: "Families’ names.")
    var families: [String] = []

    @Option(help: "Every font in this folder.")
    var folder: String?

    @Option(help: "Every family with this tag.")
    var tag: String?

    @Flag(help: "Until Cicero quits. Only while Cicero is open.")
    var untilQuit = false

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await write(.activate(families: families, folder: folder, tag: tag, untilQuit: untilQuit), common, hidden.shown)
    }
}

struct Deactivate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Turn off families, a folder’s fonts or a tag’s families.",
        aliases: ["off"]
    )

    @Argument(help: "Families’ names.")
    var families: [String] = []

    @Option(help: "Every font in this folder.")
    var folder: String?

    @Option(help: "Every family with this tag.")
    var tag: String?

    @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await write(.deactivate(families: families, folder: folder, tag: tag), common, hidden.shown)
    }
}

struct Tag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make a tag, or give one to families or take it off them.",
        subcommands: [Create.self, Add.self, Remove.self]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a tag. Nothing changes when there’s one of that name.")

        @Argument(help: "The tag’s name.")
        var name: String

        @Option(help: ArgumentHelp("red, orange, yellow, green, blue, purple, gray or sand. Without it, the first colour no tag has.", valueName: "colour"))
        var color: String?

        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.tagCreate(name: name, color: color), common)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Give families a tag.")

        @Argument(help: "The tag.")
        var tag: String

        @Argument(help: "Families’ names.")
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.tagAdd(tag: tag, families: families), common, hidden.shown)
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Take a tag off families.")

        @Argument(help: "The tag.")
        var tag: String

        @Argument(help: "Families’ names.")
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.tagRemove(tag: tag, families: families), common, hidden.shown)
        }
    }
}

struct Folder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make a folder, or put families in one or take them out.",
        subcommands: [Create.self, Add.self, Remove.self]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Make a folder. Nothing changes when there’s one of that name.")

        @Argument(help: "The folder’s name.")
        var name: String

        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.folderCreate(name: name), common)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Put families in a folder, every style of them.")

        @Argument(help: "The folder: its name or id.")
        var folder: String

        @Argument(help: "Families’ names.")
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.folderAdd(folder: folder, families: families), common, hidden.shown)
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Take families out of a folder.")

        @Argument(help: "The folder: its name or id.")
        var folder: String

        @Argument(help: "Families’ names.")
        var families: [String] = []

        @OptionGroup(title: "Hidden fonts") var hidden: ShownOptions
        @OptionGroup var common: CommonOptions

        func run() async throws {
            try await write(.folderRemove(folder: folder, families: families), common, hidden.shown)
        }
    }
}
