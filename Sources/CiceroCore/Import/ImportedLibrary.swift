import Foundation

/// A font another font manager names: by its file, its PostScript name, or its family and style, as much as it knows.
public struct ImportedFont: Hashable, Sendable {
    public var path: String?
    public var postScriptName: String?
    public var family: String?
    public var style: String?

    public init(path: String? = nil, postScriptName: String? = nil, family: String? = nil, style: String? = nil) {
        self.path = path
        self.postScriptName = postScriptName
        self.family = family
        self.style = style
    }
}

/// What another font manager has, read from its database or files, for the Import sheet to show and `LibraryImport` to
/// bring into Cicero.
public struct ImportedLibrary: Sendable {
    public enum Source: String, Sendable {
        case fontExplorer
        case fontBook

        /// The app's name, for the sheet and messages.
        public var appName: String {
            switch self {
            case .fontExplorer: "FontExplorer X"
            case .fontBook: "Font Book"
            }
        }
    }

    public var source: Source
    /// The folder the other app kept its fonts in, to list where it is: FontExplorer X's Font Library.
    public var fontFolder: String?
    /// How many font files are in `fontFolder`, for the sheet.
    public var fontFolderCount = 0
    /// Font files the other app used from other places, outside the Fonts folders and `fontFolder`.
    public var otherFiles: [String] = []
    public var sets: [ImportedSet] = []
    public var smartSets: [ImportedSmartSet] = []
    /// FontExplorer X's labels, as tags named after their colours.
    public var tags: [ImportedTag] = []
    /// Stars the other app gave single styles, 1…5.
    public var ratings: [ImportedRating] = []
    /// The classifications FontExplorer X gave single styles.
    public var classifications: [ImportedClassification] = []
    /// Comments on font files or single styles, for their families' notes.
    public var comments: [ImportedComment] = []
    /// How often the other app turned font files on, and when last.
    public var history: [ImportedHistory] = []
    /// Fonts that were on in the other app.
    public var active: [ImportedFont] = []
    /// Fonts in a backup to put in `fontFolder` before anything else: their folder in the unzipped backup, and their
    /// paths under it, which are their paths under `fontFolder` too.
    public var bundledFonts: (folder: URL, files: [String])?
    /// What doesn't come over, for the sheet: "12 comments".
    public var notes: [String] = []
    /// A temporary folder the reader made, to remove when done (see `discard`).
    var temporaryFolder: URL?

    public init(source: Source) {
        self.source = source
    }

    /// Removes what reading it left in temporary folders; call when done with it.
    public func discard() {
        if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
    }
}

/// A set, collection or application set of the other app.
public struct ImportedSet: Identifiable, Hashable, Sendable {
    /// The other app's own: FontExplorer X's serial number, a Font Book collection's file name.
    public var id: String
    /// "Folder / Set" for a set in a folder: Cicero's sets aren't in folders.
    public var name: String
    /// Its styles, each on its own.
    public var fonts: [ImportedFont] = []
    /// Families it has whole, by name: Font Book's.
    public var families: [String] = []
    /// Styles of those families it leaves out, by PostScript name.
    public var excluded: Set<String> = []
    /// For an application set, the apps it's for, where they were.
    public var apps: [String] = []
    public var isApplicationSet = false
    /// One the other app made itself, like Font Book's Fun or Web, which the sheet doesn't pick at first.
    public var isBuiltIn = false

    public init(id: String, name: String, fonts: [ImportedFont] = [], families: [String] = [], excluded: Set<String> = [],
                apps: [String] = [], isApplicationSet: Bool = false, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.fonts = fonts
        self.families = families
        self.excluded = excluded
        self.apps = apps
        self.isApplicationSet = isApplicationSet
        self.isBuiltIn = isBuiltIn
    }

    /// Its styles and whole families, for the sheet.
    public var count: Int { fonts.count + families.count }
}

/// A smart set of the other app, with its rules in Cicero's terms.
public struct ImportedSmartSet: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var matchAll: Bool
    /// Its rules as Cicero's. A Set rule's value is the `ImportedSet.id` of the set it names, until that set is
    /// imported and has Cicero's.
    public var rules: [SmartRule]
    /// The rules Cicero has no counterpart for, by what they ask: "Format", "Family Name ends with". A smart set with
    /// any of them isn't imported: without them it would pick other fonts.
    public var unsupported: [String]

    public init(id: String, name: String, matchAll: Bool, rules: [SmartRule], unsupported: [String] = []) {
        self.id = id
        self.name = name
        self.matchAll = matchAll
        self.rules = rules
        self.unsupported = unsupported
    }
}

/// A tag for the fonts the other app marked one way: one of FontExplorer X's labels.
public struct ImportedTag: Hashable, Sendable {
    public var name: String
    public var color: TagColor?
    public var fonts: [ImportedFont]

    public init(name: String, color: TagColor?, fonts: [ImportedFont]) {
        self.name = name
        self.color = color
        self.fonts = fonts
    }
}

/// The classification the other app gave a style: one of Cicero's, or one the user made there.
public struct ImportedClassification: Hashable, Sendable {
    public var font: ImportedFont
    /// One of Cicero's, or nil for the user's own.
    public var builtIn: Classification?
    /// The user's own classification's name.
    public var name: String

    public init(font: ImportedFont, builtIn: Classification) {
        self.font = font
        self.builtIn = builtIn
        name = builtIn.rawValue
    }

    public init(font: ImportedFont, custom name: String) {
        self.font = font
        builtIn = nil
        self.name = name
    }
}

public struct ImportedRating: Hashable, Sendable {
    public var font: ImportedFont
    public var stars: Int

    public init(font: ImportedFont, stars: Int) {
        self.font = font
        self.stars = stars
    }
}

/// A comment on a font file or a style, for its family's note.
public struct ImportedComment: Hashable, Sendable {
    public var fonts: [ImportedFont]
    public var text: String

    public init(fonts: [ImportedFont], text: String) {
        self.fonts = fonts
        self.text = text
    }
}

/// How often the other app turned a font file on, and when last, for the font's family.
public struct ImportedHistory: Hashable, Sendable {
    public var fonts: [ImportedFont]
    public var count: Int
    public var last: Date?

    public init(fonts: [ImportedFont], count: Int, last: Date?) {
        self.fonts = fonts
        self.count = count
        self.last = last
    }
}
