import Foundation

public enum FontBookImport {
    public static let fileExtension = "collection"

    static let builtInNames: Set<String> = ["Fixed Width", "Fun", "Modern", "PDF", "Traditional", "Web"]

    public static func collections(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let folder = home.appendingPathComponent("Library/FontCollections", isDirectory: true).resolvingSymlinksInPath()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return url.pathExtension == fileExtension && (!name.hasPrefix("com.apple.") || name == "com.apple.Favorites")
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func read(_ urls: [URL]) -> ImportedLibrary {
        var library = ImportedLibrary(source: .fontBook)
        var smart: [String] = []
        var unreadable: [String] = []
        for url in urls {
            let fileName = url.deletingPathExtension().lastPathComponent
            guard let collection = try? collection(at: url) else {
                unreadable.append(url.lastPathComponent)
                continue
            }
            // Font Book shows a collection by its file's name; the one inside can be another, as Fixed Width's is.
            // A "/" in a name the Finder shows is a ":" in the file's name on disk.
            let name = fileName == "com.apple.Favorites" ? "Favorites" : fileName.replacingOccurrences(of: ":", with: "/")
            guard let set = collection.set(id: url.lastPathComponent, name: name, isBuiltIn: builtInNames.contains(fileName)) else {
                smart.append(name)
                continue
            }
            library.sets.append(set)
        }
        if !smart.isEmpty {
            library.notes.append(smart.count == 1 ? "the smart collection “\(smart[0])”"
                : "the smart collections " + smart.map { "“\($0)”" }.listed())
        }
        if !unreadable.isEmpty {
            library.notes.append((unreadable.count == 1 ? "the file " : "the files ")
                + unreadable.map { "“\($0)”" }.listed() + ", which Cicero can’t read")
        }
        return library
    }

    struct Collection {
        var descriptors: [[String: Any]]
        var hasRules: Bool

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

    private static let namingAttributes: Set<String> = [
        "NSFontNameAttribute", "NSFontFamilyAttribute", "NSFontFaceAttribute", "NSFontVisibleNameAttribute",
        "NSFontSizeAttribute", "NSFontDescriptorNegativeAttribute",
    ]

    static func collection(at url: URL) throws -> Collection {
        let data = try Data(contentsOf: url)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.setClass(ArchivedDescriptor.self, forClassName: "NSFontDescriptor")
        // The file is anyone's: trust nothing in it, decode only these plain classes, and font descriptors as their attributes alone.
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
