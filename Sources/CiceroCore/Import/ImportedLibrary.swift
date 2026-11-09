import Foundation

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

public struct ImportedLibrary: Sendable {
    public enum Source: String, Sendable {
        case fontExplorer
        case fontBook
        case fontBase

        public var appName: String {
            switch self {
            case .fontExplorer: "FontExplorer X"
            case .fontBook: "Font Book"
            case .fontBase: "FontBase"
            }
        }
    }

    public var source: Source
    public var fontFolder: String?
    public var fontFolderCount = 0
    public var fontFolderFiles: [String] = []
    public var otherFiles: [String] = []
    public var sets: [ImportedSet] = []
    public var smartSets: [ImportedSmartSet] = []
    public var tags: [ImportedTag] = []
    public var ratings: [ImportedRating] = []
    public var classifications: [ImportedClassification] = []
    public var comments: [ImportedComment] = []
    public var history: [ImportedHistory] = []
    public var active: [ImportedFont] = []
    public var leftoverCopies: [String] = []
    public var bundledFonts: (folder: URL, files: [String])?
    public var notes: [String] = []
    var temporaryFolder: URL?

    public init(source: Source) {
        self.source = source
    }

    public func discard() {
        if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
    }
}

public struct ImportedSet: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var fonts: [ImportedFont] = []
    public var families: [String] = []
    public var excluded: Set<String> = []
    public var apps: [String] = []
    public var isApplicationSet = false
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

    public var count: Int { fonts.count + families.count }
}

public struct ImportedSmartSet: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var matchAll: Bool
    public var rules: [SmartRule]
    public var unsupported: [String]

    public init(id: String, name: String, matchAll: Bool, rules: [SmartRule], unsupported: [String] = []) {
        self.id = id
        self.name = name
        self.matchAll = matchAll
        self.rules = rules
        self.unsupported = unsupported
    }
}

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

public struct ImportedClassification: Hashable, Sendable {
    public var font: ImportedFont
    public var builtIn: Classification?
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

public struct ImportedComment: Hashable, Sendable {
    public var fonts: [ImportedFont]
    public var text: String

    public init(fonts: [ImportedFont], text: String) {
        self.fonts = fonts
        self.text = text
    }
}

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
