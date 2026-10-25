import AppKit

/// The search field's tokens (`SearchToken`) tinted with the highlight colour, the one selected text has (Appearance
/// in System Settings), rather than in SwiftUI's grey. `.searchable(text:tokens:)` puts SwiftUI's own cell in the
/// field, a subclass of AppKit's `NSTokenAttachmentCell` whose `drawTokenWithFrame:inView:` fills the token with
/// `quaternaryLabelColor`. AppKit's `drawWithFrame:inView:`, which draws every token and calls that method, gives
/// SwiftUI's class AppKit's method back the first time it draws one of its tokens, so even the first token shows
/// tinted, and a `tokenTintColor` of the highlight colour, which AppKit lays over the field lightly (with no tint, its
/// tokens take the accent colour, stronger). SwiftUI's class still places the title. When either class or a method
/// isn't there, the tokens stay grey.
enum SearchTokenTint {
    private typealias Draw = @convention(c) (NSCell, Selector, NSRect, NSView) -> Void
    private static var isInstalled = false
    /// The token cell classes `drawWithFrame:inView:` has seen, tinted or not.
    private static var seen: Set<ObjectIdentifier> = []

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        let drawToken = NSSelectorFromString("drawTokenWithFrame:inView:")
        let tint = NSSelectorFromString("tokenTintColor")
        let draw = #selector(NSCell.draw(withFrame:in:))
        guard let appKitCell = NSClassFromString("NSTokenAttachmentCell"),
              let appKitDrawToken = class_getInstanceMethod(appKitCell, drawToken),
              let appKitTint = class_getInstanceMethod(appKitCell, tint),
              let appKitDraw = class_getInstanceMethod(appKitCell, draw) else { return }
        let highlight: @convention(block) (NSCell) -> NSColor = { _ in .selectedTextBackgroundColor }
        let tintImplementation = imp_implementationWithBlock(highlight)
        let appKit = unsafeBitCast(method_getImplementation(appKitDraw), to: Draw.self)
        let tinted: @convention(block) (NSCell, NSRect, NSView) -> Void = { cell, frame, view in
            if let type = object_getClass(cell), seen.insert(ObjectIdentifier(type)).inserted,
               NSStringFromClass(type).hasPrefix("SwiftUI.") {
                class_replaceMethod(type, drawToken, method_getImplementation(appKitDrawToken), method_getTypeEncoding(appKitDrawToken))
                class_replaceMethod(type, tint, tintImplementation, method_getTypeEncoding(appKitTint))
            }
            appKit(cell, draw, frame, view)
        }
        let implementation = imp_implementationWithBlock(tinted)
        // Into NSTokenAttachmentCell itself, which has the method today; added there if it only inherits it.
        if !class_addMethod(appKitCell, draw, implementation, method_getTypeEncoding(appKitDraw)) {
            method_setImplementation(appKitDraw, implementation)
        }
    }
}
