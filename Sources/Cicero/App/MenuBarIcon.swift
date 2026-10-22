import AppKit

// Written by scripts/make-menu-bar-icon.py from the app icon's cube and font. Don't edit.
enum MenuBarIcon {
    /// The cube, `height` points high, as a template image, which the menu bar draws in its own colour, black or white:
    /// the letters cut out, and where the faces meet, so it still reads as a cube in one colour.
    static func image(height: CGFloat) -> NSImage {
        let scale = height / 690.0
        let image = NSImage(size: NSSize(width: (597.6 * scale).rounded(.up), height: height), flipped: true) { _ in
            // One path, so no seam of half-covered pixels shows where two faces meet.
            let cube = NSBezierPath()
            for face in [top(), left(), right()] { cube.append(face) }
            cube.transform(using: AffineTransform(scale: scale))
            cube.windingRule = .evenOdd
            NSColor.black.set()
            cube.fill()
            let seams = Self.seams()
            seams.transform(using: AffineTransform(scale: scale))
            // At least a pixel, so the cuts stay sharp on a screen at 1x.
            let pixelsPerPoint = NSGraphicsContext.current?.cgContext.convertToDeviceSpace(CGSize(width: 1, height: 1)).width ?? 1
            seams.lineWidth = max(0.75, 1 / max(pixelsPerPoint, 1))
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            seams.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }

    /// From the near corner, where the three faces meet, to the cube's outline.
    private static func seams() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 298.8, y: 345.0))
        path.line(to: NSPoint(x: 0.0, y: 172.5))
        path.move(to: NSPoint(x: 298.8, y: 345.0))
        path.line(to: NSPoint(x: 597.6, y: 172.5))
        path.move(to: NSPoint(x: 298.8, y: 345.0))
        path.line(to: NSPoint(x: 298.8, y: 690.0))
        return path
    }

    /// The top face, with its one cut out.
    private static func top() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.0, y: 172.5))
        path.line(to: NSPoint(x: 298.8, y: 345.0))
        path.line(to: NSPoint(x: 597.6, y: 172.5))
        path.line(to: NSPoint(x: 298.8, y: 0.0))
        path.close()
        path.move(to: NSPoint(x: 152.4, y: 198.4))
        path.line(to: NSPoint(x: 266.3, y: 264.1))
        path.line(to: NSPoint(x: 281.0, y: 255.6))
        path.line(to: NSPoint(x: 272.2, y: 250.6))
        path.curve(to: NSPoint(x: 266.0, y: 222.6), controlPoint1: NSPoint(x: 253.4, y: 239.7), controlPoint2: NSPoint(x: 248.1, y: 232.9))
        path.line(to: NSPoint(x: 421.4, y: 132.9))
        path.line(to: NSPoint(x: 400.5, y: 120.9))
        path.line(to: NSPoint(x: 304.0, y: 96.6))
        path.line(to: NSPoint(x: 279.1, y: 111.0))
        path.line(to: NSPoint(x: 362.6, y: 126.7))
        path.line(to: NSPoint(x: 235.8, y: 199.9))
        path.curve(to: NSPoint(x: 184.2, y: 199.8), controlPoint1: NSPoint(x: 213.3, y: 212.9), controlPoint2: NSPoint(x: 201.3, y: 209.6))
        path.line(to: NSPoint(x: 167.1, y: 189.9))
        path.line(to: NSPoint(x: 152.4, y: 198.4))
        path.close()
        return path
    }

    /// The left face, with its C cut out.
    private static func left() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.0, y: 517.5))
        path.line(to: NSPoint(x: 298.8, y: 690.0))
        path.line(to: NSPoint(x: 298.8, y: 345.0))
        path.line(to: NSPoint(x: 0.0, y: 172.5))
        path.close()
        path.move(to: NSPoint(x: 164.0, y: 527.5))
        path.curve(to: NSPoint(x: 84.0, y: 390.3), controlPoint1: NSPoint(x: 115.0, y: 499.3), controlPoint2: NSPoint(x: 84.0, y: 446.2))
        path.curve(to: NSPoint(x: 160.8, y: 342.2), controlPoint1: NSPoint(x: 84.0, y: 333.7), controlPoint2: NSPoint(x: 114.8, y: 315.7))
        path.curve(to: NSPoint(x: 240.2, y: 453.9), controlPoint1: NSPoint(x: 197.4, y: 363.4), controlPoint2: NSPoint(x: 222.8, y: 399.7))
        path.line(to: NSPoint(x: 252.8, y: 461.1))
        path.line(to: NSPoint(x: 252.8, y: 380.5))
        path.line(to: NSPoint(x: 238.0, y: 372.0))
        path.line(to: NSPoint(x: 224.4, y: 385.8))
        path.curve(to: NSPoint(x: 154.9, y: 319.1), controlPoint1: NSPoint(x: 207.6, y: 359.4), controlPoint2: NSPoint(x: 184.3, y: 336.1))
        path.curve(to: NSPoint(x: 43.9, y: 369.9), controlPoint1: NSPoint(x: 96.6, y: 285.4), controlPoint2: NSPoint(x: 43.9, y: 296.7))
        path.curve(to: NSPoint(x: 155.1, y: 549.9), controlPoint1: NSPoint(x: 43.9, y: 437.5), controlPoint2: NSPoint(x: 90.4, y: 512.5))
        path.curve(to: NSPoint(x: 254.9, y: 518.9), controlPoint1: NSPoint(x: 208.1, y: 580.5), controlPoint2: NSPoint(x: 247.4, y: 569.2))
        path.line(to: NSPoint(x: 239.1, y: 509.8))
        path.curve(to: NSPoint(x: 164.0, y: 527.5), controlPoint1: NSPoint(x: 229.5, y: 542.2), controlPoint2: NSPoint(x: 202.5, y: 549.8))
        path.close()
        return path
    }

    /// The right face, with its six cut out.
    private static func right() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 298.8, y: 690.0))
        path.line(to: NSPoint(x: 597.6, y: 517.5))
        path.line(to: NSPoint(x: 597.6, y: 172.5))
        path.line(to: NSPoint(x: 298.8, y: 345.0))
        path.close()
        path.move(to: NSPoint(x: 484.1, y: 357.2))
        path.line(to: NSPoint(x: 523.5, y: 334.5))
        path.curve(to: NSPoint(x: 457.4, y: 310.6), controlPoint1: NSPoint(x: 517.6, y: 295.9), controlPoint2: NSPoint(x: 493.2, y: 289.9))
        path.curve(to: NSPoint(x: 370.7, y: 481.4), controlPoint1: NSPoint(x: 403.4, y: 341.8), controlPoint2: NSPoint(x: 370.7, y: 408.8))
        path.curve(to: NSPoint(x: 451.2, y: 544.8), controlPoint1: NSPoint(x: 370.7, y: 549.6), controlPoint2: NSPoint(x: 401.2, y: 573.7))
        path.curve(to: NSPoint(x: 525.6, y: 426.8), controlPoint1: NSPoint(x: 494.8, y: 519.6), controlPoint2: NSPoint(x: 525.6, y: 470.7))
        path.curve(to: NSPoint(x: 461.1, y: 392.7), controlPoint1: NSPoint(x: 525.6, y: 383.0), controlPoint2: NSPoint(x: 500.5, y: 370.0))
        path.curve(to: NSPoint(x: 407.9, y: 458.7), controlPoint1: NSPoint(x: 437.3, y: 406.5), controlPoint2: NSPoint(x: 416.7, y: 433.5))
        path.curve(to: NSPoint(x: 456.6, y: 329.6), controlPoint1: NSPoint(x: 407.7, y: 394.9), controlPoint2: NSPoint(x: 426.6, y: 346.9))
        path.curve(to: NSPoint(x: 484.1, y: 357.2), controlPoint1: NSPoint(x: 473.4, y: 319.8), controlPoint2: NSPoint(x: 483.6, y: 325.4))
        path.close()
        path.move(to: NSPoint(x: 410.6, y: 497.9))
        path.curve(to: NSPoint(x: 451.5, y: 420.5), controlPoint1: NSPoint(x: 410.6, y: 464.8), controlPoint2: NSPoint(x: 426.4, y: 435.0))
        path.curve(to: NSPoint(x: 488.2, y: 451.9), controlPoint1: NSPoint(x: 474.0, y: 407.5), controlPoint2: NSPoint(x: 488.2, y: 419.7))
        path.curve(to: NSPoint(x: 450.2, y: 526.9), controlPoint1: NSPoint(x: 488.2, y: 484.6), controlPoint2: NSPoint(x: 473.4, y: 513.5))
        path.curve(to: NSPoint(x: 410.6, y: 497.9), controlPoint1: NSPoint(x: 425.8, y: 541.0), controlPoint2: NSPoint(x: 410.6, y: 529.7))
        path.close()
        return path
    }
}
