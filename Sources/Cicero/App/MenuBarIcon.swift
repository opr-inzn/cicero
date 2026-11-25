import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 18), flipped: true) { _ in
            let pilcrow = NSBezierPath()
            pilcrow.move(to: NSPoint(x: 7.462, y: 2.526))
            pilcrow.line(to: NSPoint(x: 7.462, y: 16.518))
            pilcrow.line(to: NSPoint(x: 8.798, y: 16.518))
            pilcrow.line(to: NSPoint(x: 8.798, y: 3.738))
            pilcrow.curve(to: NSPoint(x: 9.842, y: 2.526), controlPoint1: NSPoint(x: 8.798, y: 2.694), controlPoint2: NSPoint(x: 9.007, y: 2.547))
            pilcrow.line(to: NSPoint(x: 10.97, y: 2.485))
            pilcrow.line(to: NSPoint(x: 10.97, y: 1.482))
            pilcrow.line(to: NSPoint(x: 4.872, y: 1.482))
            pilcrow.curve(to: NSPoint(x: 1.03, y: 4.928), controlPoint1: NSPoint(x: 2.575, y: 1.482), controlPoint2: NSPoint(x: 1.03, y: 3.028))
            pilcrow.curve(to: NSPoint(x: 4.872, y: 8.374), controlPoint1: NSPoint(x: 1.03, y: 6.828), controlPoint2: NSPoint(x: 2.575, y: 8.374))
            pilcrow.line(to: NSPoint(x: 4.872, y: 16.518))
            pilcrow.line(to: NSPoint(x: 6.209, y: 16.518))
            pilcrow.line(to: NSPoint(x: 6.209, y: 2.526))
            pilcrow.close()
            NSColor.black.set()
            pilcrow.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cicero"
        return image
    }
}
