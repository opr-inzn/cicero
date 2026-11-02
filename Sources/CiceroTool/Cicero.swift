import ArgumentParser
import CiceroCommands
import Foundation

@main
struct Cicero: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cicero",
        abstract: "Find and check the fonts in Cicero’s library.",
        discussion: """
            Reads what Cicero saved: it works while Cicero is closed too, and never opens it. Add --json for answers \
            that scripts and agents read; their fields are in the help page.
            """,
        version: Version.text,
        subcommands: [Status.self, Find.self, CoverageCheck.self, List.self]
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

func load(_ common: CommonOptions, rescan: Bool = false) async throws -> LibraryContext {
    let start = ContinuousClock.now
    let context = try await LibraryContext.load(.current(), rescan: rescan)
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

    @Flag(help: "Scan the font folders first. Only while Cicero is closed.")
    var rescan = false

    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.status) {
            let context = try await load(common, rescan: rescan)
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
    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.families) {
            try FindCommand.run(find.options(words: words), in: try await load(common))
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

    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: Text.coverageCheck) {
            try await CoverageCommand.run(family: family, set: set, text: text, in: try await load(common))
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

    @OptionGroup var common: CommonOptions

    func run() async throws {
        try await answer(common, text: { Text.list(what, $0) }) {
            var options = FindOptions()
            options.limit = limit
            options.offset = offset
            return try ListCommand.run(what, options: options, in: try await load(common))
        }
    }
}
