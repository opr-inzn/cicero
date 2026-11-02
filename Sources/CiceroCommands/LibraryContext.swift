import AppKit
import CiceroCore
import Foundation

/// Fonts Cicero's settings hide or show, which one command shows or hides instead; nil keeps Cicero's setting. It never
/// changes the setting.
public struct ShownFonts: Sendable, Equatable {
    /// Those that come with macOS (Show system fonts).
    public var systemFonts: Bool?
    /// Adobe Fonts from Creative Cloud (Show fonts from Creative Cloud).
    public var adobeFonts: Bool?
    /// Those in the folders Adobe apps load by themselves (Show fonts installed for proofing in Adobe apps).
    public var proofingFonts: Bool?

    public init(systemFonts: Bool? = nil, adobeFonts: Bool? = nil, proofingFonts: Bool? = nil) {
        self.systemFonts = systemFonts
        self.adobeFonts = adobeFonts
        self.proofingFonts = proofingFonts
    }

    /// The user's data with these in place of Cicero's settings.
    func applied(to data: UserData) -> UserData {
        var data = data
        if let systemFonts { data.showSystemFonts = systemFonts }
        if let adobeFonts { data.showCreativeCloudFonts = adobeFonts }
        if let proofingFonts { data.showAdobeAppFolders = proofingFonts }
        return data
    }
}

/// What the read commands read, as Cicero saved it: the user's data, the library the last scan saved with each face on
/// or off as macOS has it now, the coverage worked out so far and the guessed classifications. Reads never scan
/// unless asked to (`rescan`), or unless the proofing fonts are to be shown or hidden other than as the saved library
/// was scanned. Only a scan as Cicero makes it, while Cicero is closed, is saved: while it's open, Cicero writes its
/// caches itself, and would write over the tool's or keep showing its own.
public final class LibraryContext: @unchecked Sendable {
    public let environment: ToolEnvironment
    public let data: UserData
    public let library: Library
    /// When the library was last scanned (saved by a scan).
    public let lastScan: Date?
    public let characterSets: CharacterSetCatalog?
    public let coverage: CoverageIndex?
    /// The guessed classification of a family nothing in its files classifies, as the app has it.
    public let classificationGuess: (Family) -> Classification?

    /// Loads everything; `rescan` scans first. `shown` shows or hides fonts other than as Cicero's settings do.
    public static func load(_ environment: ToolEnvironment, rescan: Bool = false, shown: ShownFonts = ShownFonts()) async throws -> LibraryContext {
        let saved = try loadUserData(environment)
        let data = shown.applied(to: saved)
        // The saved library has the proofing fonts as Cicero's setting has them; the other way needs a scan of its own.
        let proofingDiffers = data.showAdobeAppFolders != saved.showAdobeAppFolders && !environment.appFontFolders.isEmpty
        let scans = rescan || proofingDiffers
        let saves = scans && !proofingDiffers && !isAppOpen(environment)
        let scanner = LibraryScanner(locations: environment.locations, registrar: environment.registrar, saves: saves)
        let languages = environment.resources.map { LanguageCatalog(contentsOf: $0.appendingPathComponent("Languages.json")) }
        let coverage = languages.map { CoverageIndex(caches: environment.locations.caches, languages: $0) }
        let library: Library
        let lastScan: Date?
        if scans {
            library = try await scanner.scan(ScanInput(folders: data.scannedFolders(appFolders: environment.appFontFolders), files: data.fontFiles, records: data.records)) { _ in }
            if saves {
                scanner.flush()
                // As the app keeps it: the families its settings list.
                await coverage?.update(library.families.filter(saved.lists)) { _, _ in }
                coverage?.waitForSave()
            }
            lastScan = environment.now
        } else {
            guard let saved = scanner.savedLibraryAsNow(records: data.records) else {
                throw CommandError(.failed, "Cicero hasn't scanned the fonts yet. Open Cicero once, or run the command again with --rescan.")
            }
            library = saved.library
            lastScan = saved.lastSaved
        }
        coverage?.loadSaved()
        // The coverage the saved cache can lack: of what a scan that isn't saved found, and of fonts Cicero hides that
        // this command shows. Worked out now, and not saved.
        let showsMore = (data.showSystemFonts && !saved.showSystemFonts) || (data.showCreativeCloudFonts && !saved.showCreativeCloudFonts)
        if (scans && !saves) || showsMore {
            await coverage?.update(library.families.filter(data.lists), saves: false) { _, _ in }
        }
        let characterSets = environment.resources.map { CharacterSetCatalog(contentsOf: $0.appendingPathComponent("CharacterSets.json")) }
        let measurements = MeasurementIndex(caches: environment.locations.caches)
        measurements.loadSaved()
        let rule = ClassificationGuesses.rule(
            names: ClassificationGuesses.savedNames(caches: environment.locations.caches),
            letters: ClassificationGuesses.letters(of: library.families, measurements: measurements),
            guessing: ClassificationGuesses.isGuessing(environment.defaults)
        )
        return LibraryContext(environment: environment, data: data, library: library, lastScan: lastScan, characterSets: characterSets,
                              coverage: coverage, classificationGuess: { rule($0)?.classification })
    }

    init(environment: ToolEnvironment, data: UserData, library: Library, lastScan: Date?, characterSets: CharacterSetCatalog?,
         coverage: CoverageIndex?, classificationGuess: @escaping (Family) -> Classification?) {
        self.environment = environment
        self.data = data
        self.library = library
        self.lastScan = lastScan
        self.characterSets = characterSets
        self.coverage = coverage
        self.classificationGuess = classificationGuess
    }

    /// user-data.json as the app reads it, but a file that can't be read stops the command: the app keeps such a file
    /// aside and starts again, which the tool leaves to it.
    static func loadUserData(_ environment: ToolEnvironment) throws -> UserData {
        let url = environment.userDataURL
        var data: UserData
        if let contents = try? Data(contentsOf: url) {
            do {
                data = try JSONDecoder().decode(UserData.self, from: contents)
            } catch {
                throw CommandError(.unreadableUserData, "Cicero’s data can’t be read (\(url.path)). Open Cicero: it keeps the file aside and starts again.")
            }
            data.updateLicenseTags()
        } else if FileManager.default.fileExists(atPath: url.path) {
            throw CommandError(.unreadableUserData, "Cicero’s data can’t be read (\(url.path)).")
        } else {
            data = .newLibrary
        }
        // As the app does for files from before there was a Font Library.
        if data.fontLibraryPath.isEmpty { data.fontLibraryPath = environment.locations.defaultFontLibrary.path }
        return data
    }

    /// Whether Cicero is open (for this user).
    public static func isAppOpen(_ environment: ToolEnvironment) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: environment.appBundleID).isEmpty
    }

    // MARK: What the app shows

    /// The fonts this command hides, by Cicero's settings or its own flags: `systemFonts`, `adobeFonts`, `proofingFonts`.
    public var hidden: [String] {
        [("systemFonts", data.showSystemFonts), ("adobeFonts", data.showCreativeCloudFonts), ("proofingFonts", data.showAdobeAppFolders)]
            .filter { !$0.1 }.map(\.0)
    }

    /// The families the app lists: not those that come with macOS or from Creative Cloud while they're hidden.
    public lazy var listedFamilies: [Family] = library.families.filter(data.lists)

    public lazy var filters = FamilyFilters(
        library: library, data: data, classificationGuess: classificationGuess,
        coverage: CoverageAnswers(
            characterSet: { [unowned self] in self.characterSet($0) },
            missingCount: { [unowned self] set, family in self.missingCount(set, family.regular.face) },
            supports: { [unowned self] family, language in self.faceCoverage(family.regular.face)?.support(for: language).map { _ in true } ?? false }
        ),
        now: environment.now
    )

    public lazy var foundryName: (Family) -> String? = data.foundryNamer()
    public lazy var classificationName: (Family) -> String = data.classificationNamer(guess: classificationGuess)

    // MARK: Coverage

    /// The user's character sets, as definitions.
    public lazy var customSets: [CharacterSetDefinition] = data.customCharacterSets.enumerated().map {
        CharacterSetCatalog.definition(for: $1, level: $0)
    }

    /// Built-in sets, then the user's.
    public var allSets: [CharacterSetDefinition] { (characterSets?.builtIn ?? []) + customSets }

    public func characterSet(_ id: String) -> CharacterSetDefinition? {
        id.hasPrefix("custom.") ? customSets.first { $0.id == id } : characterSets?.definition(id)
    }

    /// The face's coverage as worked out so far; nil while not checked yet.
    public func faceCoverage(_ face: FontFace) -> FaceCoverage? {
        coverage?.coverage(of: face.id)
    }

    /// The face's coverage, worked out now when it isn't yet (reading its file).
    public func faceCoverage(computing face: FontFace) async -> FaceCoverage? {
        guard let coverage else { return nil }
        return await coverage.coverage(computing: face)
    }

    private var missingCounts: [String: [FaceID: Int]] = [:]

    /// How many of the set's characters the face lacks; nil while not checked yet.
    public func missingCount(_ set: CharacterSetDefinition, _ face: FontFace) -> Int? {
        if let known = missingCounts[set.id]?[face.id] { return known }
        guard let scalars = faceCoverage(face)?.scalars else { return nil }
        let missing = scalars.missingCount(sorted: set.scalars)
        missingCounts[set.id, default: [:]][face.id] = missing
        return missing
    }

    /// The largest set of a series the face has every character of.
    public func largest(in seriesID: String, for face: FontFace) -> CharacterSetDefinition? {
        guard let series = characterSets?.series.first(where: { $0.id == seriesID }) else { return nil }
        return series.sets.last { missingCount($0, face) == 0 }
    }
}
