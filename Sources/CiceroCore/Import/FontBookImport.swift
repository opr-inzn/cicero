import Foundation

/// Reads Font Book's collections: `.collection` files in ~/Library/FontCollections, or ones copied from another Mac.
/// Each is a keyed archive of a dictionary whose NSFontCollectionFontDescriptors name the fonts it has: a family whole
/// (its family name), a style (its PostScript name), or a style left out of a family (marked negative). A smart
/// collection, or Font Book's Fixed Width, picks fonts by what they are instead, which isn't read.
public enum FontBookImport {
    public static let fileExtension = "collection"

    /// Collections Font Book makes itself, which the sheet doesn't pick at first.
    static let builtInNames: Set<String> = ["Fixed Width", "Fun", "Modern", "PDF", "Traditional", "Web"]

    /// The user's collections on this Mac: theirs, Font Book's own, and Favorites; not Recents or the ones Font Book
    /// keeps for itself.
    public static func collections(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let folder = home.appendingPathComponent("Library/FontCollections", isDirectory: true).resolvingSymlinksInPath()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return url.pathExtension == fileExtension && (!name.hasPrefix("com.apple.") || name == "com.apple.Favorites")
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The collections as sets; ones that pick fonts by rules, or can't be read, are named in the notes.
    public static func read(_ urls: [URL]) -> ImportedLibrary {
        var library = ImportedLibrary(source: .fontBook)
        var skipped: [String] = []
        for url in urls {
            let fileName = url.deletingPathExtension().lastPathComponent
            guard let collection = try? collection(at: url) else {
                skipped.append(fileName)
                continue
            }
            // Font Book shows a collection by its file's name; the one inside can be another, as Fixed Width's is.
            let name = fileName == "com.apple.Favorites" ? "Favorites" : fileName
            guard let set = collection.set(id: url.lastPathComponent, name: name, isBuiltIn: builtInNames.contains(fileName)) else {
                skipped.append(name)
                continue
            }
            library.sets.append(set)
        }
        if !skipped.isEmpty {
            library.notes.append(skipped.count == 1 ? "the smart collection “\(skipped[0])”"
                : "the smart collections " + skipped.map { "“\($0)”" }.formatted(.list(type: .and)))
        }
        return library
    }

    struct Collection {
        var descriptors: [[String: Any]]
        /// The collection picks fonts by rules: a predicate, or descriptors asking for traits or languages.
        var hasRules: Bool

        /// The fonts it names, as a set; nil for one that picks them by rules.
        func set(id: String, name: String, isBuiltIn: Bool) -> ImportedSet? {
            guard !hasRules else { return nil }
            var set = ImportedSet(id: id, name: name, isBuiltIn: isBuiltIn)
            for attributes in descriptors {
                let postScriptName = nonEmpty(attributes["NSFontNameAttribute"])
                let family = nonEmpty(attributes["NSFontFamilyAttribute"])
                let style = nonEmpty(attributes["NSFontFaceAttribute"])
                if (attributes["NSFontDescriptorNegativeAttribute"] as? NSNumber)?.boolValue == true {
                    if let postScriptName { set.excluded.insert(postScriptName) }
                } else if postScriptName != nil || style != nil {
                    set.fonts.append(ImportedFont(postScriptName: postScriptName, family: family, style: style))
                } else if let family, !set.families.contains(family) {
                    set.families.append(family)
                }
            }
            return set
        }

        private func nonEmpty(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
    }

    /// What a descriptor may say about a font it names; any other attribute asks for fonts of a kind.
    private static let namingAttributes: Set<String> = [
        "NSFontNameAttribute", "NSFontFamilyAttribute", "NSFontFaceAttribute", "NSFontVisibleNameAttribute",
        "NSFontSizeAttribute", "NSFontDescriptorNegativeAttribute",
    ]

    /// Reads a collection file, trusting nothing in it: only dictionaries, arrays, strings, numbers, data and dates,
    /// and font descriptors as their attributes alone.
    static func collection(at url: URL) throws -> Collection {
        let data = try Data(contentsOf: url)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.setClass(ArchivedDescriptor.self, forClassName: "NSFontDescriptor")
        let classes: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self,
                                   NSSet.self, ArchivedDescriptor.self]
        let root = unarchiver.decodeObject(of: classes, forKey: "NSFontCollectionDictionary")
        unarchiver.finishDecoding()
        guard unarchiver.error == nil, let dictionary = root as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        let descriptors = (dictionary["NSFontCollectionFontDescriptors"] as? [Any] ?? []).compactMap { ($0 as? ArchivedDescriptor)?.attributes }
        let rules = dictionary.keys.contains { $0 != "NSFontCollectionFontDescriptors" && $0 != "NSFontCollectionAttributes" }
            || descriptors.contains { $0.keys.contains { !namingAttributes.contains($0) } }
            || descriptors.contains { $0["NSFontNameAttribute"] == nil && $0["NSFontFamilyAttribute"] == nil }
        return Collection(descriptors: descriptors, hasRules: rules)
    }
}

/// An NSFontDescriptor in an archive, as its attributes, read without AppKit.
@objc(CiceroArchivedFontDescriptor)
final class ArchivedDescriptor: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true
    let attributes: [String: Any]

    init?(coder: NSCoder) {
        let classes: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSSet.self]
        attributes = coder.decodeObject(of: classes, forKey: "NSFontDescriptorAttributes") as? [String: Any] ?? [:]
    }

    func encode(with coder: NSCoder) {
        coder.encode(attributes as NSDictionary, forKey: "NSFontDescriptorAttributes")
    }
}
