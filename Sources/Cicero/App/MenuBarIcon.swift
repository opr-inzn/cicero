import AppKit

// Written by scripts/make-menu-bar-icon.py from the C of the app icon's font. Don't edit.
enum MenuBarIcon {
    /// The C, `height` points high, as a template image, which the menu bar draws in its own colour.
    static func image(height: CGFloat) -> NSImage {
        let scale = height / 747
        let image = NSImage(size: NSSize(width: (789 * scale).rounded(.up), height: height), flipped: false) { _ in
            let path = outline()
            path.transform(using: AffineTransform(scale: scale))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }

    private static func outline() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 449, y: 89))
        path.curve(to: NSPoint(x: 150, y: 384), controlPoint1: NSPoint(x: 266, y: 89), controlPoint2: NSPoint(x: 150, y: 203))
        path.curve(to: NSPoint(x: 437, y: 683), controlPoint1: NSPoint(x: 150, y: 567), controlPoint2: NSPoint(x: 265, y: 683))
        path.curve(to: NSPoint(x: 734, y: 470), controlPoint1: NSPoint(x: 574, y: 683), controlPoint2: NSPoint(x: 669, y: 613))
        path.line(to: NSPoint(x: 781, y: 470))
        path.line(to: NSPoint(x: 781, y: 731))
        path.line(to: NSPoint(x: 726, y: 731))
        path.line(to: NSPoint(x: 675, y: 661))
        path.curve(to: NSPoint(x: 415, y: 747), controlPoint1: NSPoint(x: 612, y: 715), controlPoint2: NSPoint(x: 525, y: 747))
        path.curve(to: NSPoint(x: 0, y: 375), controlPoint1: NSPoint(x: 197, y: 747), controlPoint2: NSPoint(x: 0, y: 612))
        path.curve(to: NSPoint(x: 416, y: 0), controlPoint1: NSPoint(x: 0, y: 156), controlPoint2: NSPoint(x: 174, y: 0))
        path.curve(to: NSPoint(x: 789, y: 287), controlPoint1: NSPoint(x: 614, y: 0), controlPoint2: NSPoint(x: 761, y: 110))
        path.line(to: NSPoint(x: 730, y: 287))
        path.curve(to: NSPoint(x: 449, y: 89), controlPoint1: NSPoint(x: 694, y: 164), controlPoint2: NSPoint(x: 593, y: 89))
        path.close()
        return path
    }
}
