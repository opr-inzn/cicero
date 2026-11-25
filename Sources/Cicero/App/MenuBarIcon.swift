import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 18, height: 18))
            path.move(to: NSPoint(x: 9.155, y: 13.602))
            path.curve(to: NSPoint(x: 12.756, y: 10.43), controlPoint1: NSPoint(x: 11.235, y: 13.602), controlPoint2: NSPoint(x: 12.704, y: 12.328))
            path.line(to: NSPoint(x: 11.95, y: 10.43))
            path.curve(to: NSPoint(x: 9.311, y: 12.562), controlPoint1: NSPoint(x: 11.807, y: 11.886), controlPoint2: NSPoint(x: 10.806, y: 12.562))
            path.curve(to: NSPoint(x: 6.074, y: 8.87), controlPoint1: NSPoint(x: 7.348, y: 12.562), controlPoint2: NSPoint(x: 6.074, y: 11.418))
            path.curve(to: NSPoint(x: 9.168, y: 5.152), controlPoint1: NSPoint(x: 6.074, y: 6.79), controlPoint2: NSPoint(x: 6.919, y: 5.152))
            path.curve(to: NSPoint(x: 11.677, y: 6.998), controlPoint1: NSPoint(x: 10.403, y: 5.152), controlPoint2: NSPoint(x: 11.521, y: 5.581))
            path.line(to: NSPoint(x: 11.703, y: 7.232))
            path.line(to: NSPoint(x: 12.483, y: 7.232))
            path.line(to: NSPoint(x: 12.483, y: 4.97))
            path.curve(to: NSPoint(x: 9.324, y: 4.398), controlPoint1: NSPoint(x: 11.703, y: 4.697), controlPoint2: NSPoint(x: 10.416, y: 4.398))
            path.curve(to: NSPoint(x: 4.644, y: 9), controlPoint1: NSPoint(x: 6.1, y: 4.398), controlPoint2: NSPoint(x: 4.644, y: 6.465))
            path.curve(to: NSPoint(x: 9.155, y: 13.602), controlPoint1: NSPoint(x: 4.644, y: 11.626), controlPoint2: NSPoint(x: 6.373, y: 13.602))
            path.close()
            path.windingRule = .evenOdd
            NSColor.black.set()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }
}
