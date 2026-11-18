import AppKit
import CiceroCore
import SwiftUI

nonisolated extension NSMutableAttributedString {
    func showMissingAsNotdef(in font: CTFont) {
        showAsNotdef(font.missingCharacters(in: string))
    }

    fileprivate func showAsNotdef(_ ranges: [NSRange]) {
        let string = self.string as NSString
        for range in ranges where attribute(.glyphInfo, at: range.location, effectiveRange: nil) == nil {
            // By identity, not as glyph 0 of one CTFont, which SwiftUI drops once it shrinks the text to fit.
            guard let info = NSGlyphInfo(characterIdentifier: 0, collection: .identityMappingCharacterCollection,
                                         baseString: string.substring(with: range)) else { continue }
            addAttribute(.glyphInfo, value: info, range: range)
        }
    }
}

extension Text {
    init(_ string: String, notdefIn font: CTFont) {
        let missing = font.missingCharacters(in: string)
        guard !missing.isEmpty else {
            self.init(verbatim: string)
            return
        }
        let shown = NSMutableAttributedString(string: string)
        shown.showAsNotdef(missing)
        if let attributed = try? AttributedString(shown, including: \.appKit) {
            self.init(attributed)
        } else {
            self.init(verbatim: string)
        }
    }
}
