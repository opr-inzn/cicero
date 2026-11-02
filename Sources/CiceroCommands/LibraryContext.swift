import AppKit
import CiceroCore
import Foundation

/// What the read commands read, as Cicero saved it: the user's data, the library the last scan saved with each face on
/// or off as macOS has it now, the coverage worked out so far and the guessed classifications. Reads never scan
/// unless asked to (`rescan`), and never write but for what a rescan finds.
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

    /// Loads everything; `rescan` scans first, which only a closed app lets the tool do.
    public static func load(_ environment: ToolEnvironment, rescan: Bool = false) async throws -> LibraryContext {
        let data = try loadUserData(environment)
        let scanner = LibraryScanner(locations: environment.locations, registrar: environment.registrar)
        let languages = environment.resources.map { LanguageCatalog(contentsOf: $0.appendingPathComponent("Languages.json")) }
        let coverage = languages.map { CoverageIndex(caches: environment.locations.caches, languages: $0) }
        let library: Library
        let lastScan: Date?
        if rescan {
            if isAppOpen(environment) {
                throw CommandError(.busy, "Cicero is open, and it scans by itself. Quit Cicero to rescan from here, or leave out --rescan.")
            }
            library = try await scanner.scan(ScanInput(folders: data.scannedFolders(), files: data.fontFiles, records: data.records)) { _ in }
            scanner.flush()
            if let coverage {
                await coverage.update(library.families.filter(data.lists)) { _, _ in }
                coverage.waitForSave()
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
