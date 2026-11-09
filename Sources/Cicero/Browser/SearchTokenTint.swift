import AppKit

enum SearchTokenTint {
    private typealias Draw = @convention(c) (NSCell, Selector, NSRect, NSView) -> Void
    private static var isInstalled = false
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
              let appKitDraw = class_getInstanceMethod(appKitCell, draw),
              // The private method still returns an object and takes nothing, as the block standing in for it does:
              // called some other way, the block would crash.
              Self.returnsObjectOnly(appKitTint) else { return }
        let highlight: @convention(block) (NSCell) -> NSColor = { _ in highlightTint() }
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

    private static func returnsObjectOnly(_ method: Method) -> Bool {
        let returned = method_copyReturnType(method)
        defer { free(returned) }
        return String(cString: returned) == "@" && method_getNumberOfArguments(method) == 2
    }

    private static func highlightTint() -> NSColor {
        var highlight = NSColor.selectedTextBackgroundColor
        // Light mode's colour in Dark mode too: AppKit darkens the tint for Dark mode itself, and Dark mode's own highlight colour came out grey.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            highlight = NSColor.selectedTextBackgroundColor.usingColorSpace(.sRGB) ?? highlight
        }
        guard let rgb = highlight.usingColorSpace(.sRGB) else { return highlight }
        return NSColor(hue: rgb.hueComponent, saturation: min(1, rgb.saturationComponent * 2.2), brightness: rgb.brightnessComponent, alpha: 1)
    }
}
