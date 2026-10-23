import AppKit

// Written by scripts/make-menu-bar-icon.py from the app icon's cube and font. Don't edit.
enum MenuBarIcon {
    /// The cube, `height` points high, as a template image, which the menu bar draws in its own colour, black or white:
    /// the letters cut out, the faces meeting without a gap.
    static func image(height: CGFloat) -> NSImage {
        let scale = height / 800.0
        let image = NSImage(size: NSSize(width: (692.8 * scale).rounded(.up), height: height), flipped: true) { _ in
            // One path, so no seam of half-covered pixels shows where two faces meet.
            let cube = NSBezierPath()
            for face in [top(), left(), right()] { cube.append(face) }
            cube.transform(using: AffineTransform(scale: scale))
            cube.windingRule = .evenOdd
            NSColor.black.set()
            cube.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }

    /// The top face, with its one cut out.
    private static func top() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.0, y: 200.0))
        path.line(to: NSPoint(x: 346.4, y: 400.0))
        path.line(to: NSPoint(x: 692.8, y: 200.0))
        path.line(to: NSPoint(x: 346.4, y: 0.0))
        path.close()
        path.move(to: NSPoint(x: 176.5, y: 229.9))
        path.line(to: NSPoint(x: 301.1, y: 301.8))
        path.line(to: NSPoint(x: 317.4, y: 292.4))
        path.line(to: NSPoint(x: 288.7, y: 275.1))
        path.curve(to: NSPoint(x: 291.3, y: 254.8), controlPoint1: NSPoint(x: 276.0, y: 267.4), controlPoint2: NSPoint(x: 278.3, y: 262.3))
        path.line(to: NSPoint(x: 477.1, y: 147.5))
        path.line(to: NSPoint(x: 458.2, y: 136.6))
        path.line(to: NSPoint(x: 359.1, y: 117.0))
        path.line(to: NSPoint(x: 337.6, y: 129.4))
        path.line(to: NSPoint(x: 340.9, y: 131.3))
        path.line(to: NSPoint(x: 415.5, y: 146.2))
        path.line(to: NSPoint(x: 259.4, y: 236.3))
        path.curve(to: NSPoint(x: 224.1, y: 237.8), controlPoint1: NSPoint(x: 246.3, y: 243.9), controlPoint2: NSPoint(x: 237.5, y: 245.2))
        path.line(to: NSPoint(x: 192.8, y: 220.5))
        path.line(to: NSPoint(x: 176.5, y: 229.9))
        path.close()
        return path
    }

    /// The left face, with its C cut out.
    private static func left() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.0, y: 600.0))
        path.line(to: NSPoint(x: 346.4, y: 800.0))
        path.line(to: NSPoint(x: 346.4, y: 400.0))
        path.line(to: NSPoint(x: 0.0, y: 200.0))
        path.close()
        path.move(to: NSPoint(x: 184.6, y: 639.9))
        path.curve(to: NSPoint(x: 274.9, y: 600.1), controlPoint1: NSPoint(x: 236.8, y: 670.0), controlPoint2: NSPoint(x: 273.6, y: 654.4))
        path.line(to: NSPoint(x: 254.7, y: 588.5))
        path.curve(to: NSPoint(x: 188.5, y: 612.0), controlPoint1: NSPoint(x: 251.1, y: 628.6), controlPoint2: NSPoint(x: 226.0, y: 633.6))
        path.curve(to: NSPoint(x: 107.3, y: 458.2), controlPoint1: NSPoint(x: 139.3, y: 583.6), controlPoint2: NSPoint(x: 107.3, y: 532.0))
        path.curve(to: NSPoint(x: 184.9, y: 395.3), controlPoint1: NSPoint(x: 107.3, y: 398.0), controlPoint2: NSPoint(x: 128.5, y: 362.8))
        path.curve(to: NSPoint(x: 247.9, y: 485.1), controlPoint1: NSPoint(x: 215.9, y: 413.2), controlPoint2: NSPoint(x: 244.0, y: 441.8))
        path.line(to: NSPoint(x: 248.5, y: 492.3))
        path.line(to: NSPoint(x: 268.1, y: 503.6))
        path.line(to: NSPoint(x: 268.1, y: 438.1))
        path.curve(to: NSPoint(x: 188.9, y: 375.8), controlPoint1: NSPoint(x: 248.5, y: 418.9), controlPoint2: NSPoint(x: 216.2, y: 391.6))
        path.curve(to: NSPoint(x: 71.5, y: 441.3), controlPoint1: NSPoint(x: 108.0, y: 329.1), controlPoint2: NSPoint(x: 71.5, y: 367.9))
        path.curve(to: NSPoint(x: 184.6, y: 639.9), controlPoint1: NSPoint(x: 71.5, y: 517.3), controlPoint2: NSPoint(x: 114.8, y: 599.6))
        path.close()
        return path
    }

    /// The right face, with its six cut out.
    private static func right() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 346.4, y: 800.0))
        path.line(to: NSPoint(x: 692.8, y: 600.0))
        path.line(to: NSPoint(x: 692.8, y: 200.0))
        path.line(to: NSPoint(x: 346.4, y: 400.0))
        path.close()
        path.move(to: NSPoint(x: 523.2, y: 631.2))
        path.curve(to: NSPoint(x: 607.6, y: 494.7), controlPoint1: NSPoint(x: 573.4, y: 602.2), controlPoint2: NSPoint(x: 607.6, y: 547.1))
        path.curve(to: NSPoint(x: 529.4, y: 459.0), controlPoint1: NSPoint(x: 607.6, y: 447.3), controlPoint2: NSPoint(x: 577.6, y: 431.1))
        path.curve(to: NSPoint(x: 466.8, y: 525.2), controlPoint1: NSPoint(x: 501.4, y: 475.2), controlPoint2: NSPoint(x: 478.2, y: 500.9))
        path.curve(to: NSPoint(x: 533.0, y: 379.7), controlPoint1: NSPoint(x: 467.4, y: 462.0), controlPoint2: NSPoint(x: 479.5, y: 410.6))
        path.curve(to: NSPoint(x: 562.7, y: 368.2), controlPoint1: NSPoint(x: 546.0, y: 372.2), controlPoint2: NSPoint(x: 555.8, y: 368.8))
        path.curve(to: NSPoint(x: 549.6, y: 399.1), controlPoint1: NSPoint(x: 553.8, y: 378.2), controlPoint2: NSPoint(x: 549.6, y: 390.1))
        path.curve(to: NSPoint(x: 571.5, y: 411.3), controlPoint1: NSPoint(x: 549.6, y: 410.0), controlPoint2: NSPoint(x: 556.8, y: 419.8))
        path.curve(to: NSPoint(x: 595.6, y: 369.2), controlPoint1: NSPoint(x: 583.8, y: 404.2), controlPoint2: NSPoint(x: 595.6, y: 388.0))
        path.curve(to: NSPoint(x: 531.7, y: 359.8), controlPoint1: NSPoint(x: 595.6, y: 342.1), controlPoint2: NSPoint(x: 570.8, y: 337.2))
        path.curve(to: NSPoint(x: 431.6, y: 554.6), controlPoint1: NSPoint(x: 456.0, y: 403.4), controlPoint2: NSPoint(x: 431.6, y: 480.8))
        path.curve(to: NSPoint(x: 523.2, y: 631.2), controlPoint1: NSPoint(x: 431.6, y: 639.7), controlPoint2: NSPoint(x: 463.9, y: 665.5))
        path.close()
        path.move(to: NSPoint(x: 521.2, y: 611.2))
        path.curve(to: NSPoint(x: 470.1, y: 576.8), controlPoint1: NSPoint(x: 488.6, y: 630.1), controlPoint2: NSPoint(x: 470.1, y: 614.4))
        path.curve(to: NSPoint(x: 521.2, y: 484.8), controlPoint1: NSPoint(x: 470.1, y: 535.4), controlPoint2: NSPoint(x: 488.6, y: 503.6))
        path.curve(to: NSPoint(x: 572.4, y: 519.2), controlPoint1: NSPoint(x: 553.8, y: 465.9), controlPoint2: NSPoint(x: 572.4, y: 481.6))
        path.curve(to: NSPoint(x: 521.2, y: 611.2), controlPoint1: NSPoint(x: 572.4, y: 556.8), controlPoint2: NSPoint(x: 553.8, y: 592.4))
        path.close()
        return path
    }
}
