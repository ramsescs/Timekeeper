import AppKit

/// Simple friendly robot face for the menu bar, drawn as a template image so it adapts to light/dark menu bars.
enum RobotIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Head
            let head = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 1.5, width: 13, height: 11), xRadius: 3, yRadius: 3)
            head.lineWidth = 1.5
            head.stroke()

            // Ears
            NSBezierPath(roundedRect: NSRect(x: 0.5, y: 5.5, width: 1.5, height: 3), xRadius: 0.7, yRadius: 0.7).fill()
            NSBezierPath(roundedRect: NSRect(x: 16, y: 5.5, width: 1.5, height: 3), xRadius: 0.7, yRadius: 0.7).fill()

            // Antenna
            let stalk = NSBezierPath()
            stalk.move(to: NSPoint(x: 9, y: 12.5))
            stalk.line(to: NSPoint(x: 9, y: 15))
            stalk.lineWidth = 1.2
            stalk.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.7, y: 14.6, width: 2.6, height: 2.6)).fill()

            // Eyes
            NSBezierPath(ovalIn: NSRect(x: 5.4, y: 6.6, width: 2.2, height: 3.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.4, y: 6.6, width: 2.2, height: 3.2)).fill()

            // Smile
            let smile = NSBezierPath()
            smile.appendArc(withCenter: NSPoint(x: 9, y: 6.2), radius: 2.4, startAngle: 215, endAngle: 325)
            smile.lineWidth = 1.2
            smile.lineCapStyle = .round
            smile.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
