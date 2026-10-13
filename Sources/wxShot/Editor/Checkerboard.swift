import AppKit

/// Opaque preview-only backdrop so translucent pixels are not blended with the frozen desktop.
enum Checkerboard {
    static func draw(in rect: CGRect, square: CGFloat = 14) {
        guard square > 0, rect.width > 0, rect.height > 0 else { return }
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var column = 0
            while x < rect.maxX {
                (((row + column).isMultiple(of: 2))
                    ? NSColor(calibratedWhite: 0.88, alpha: 1)
                    : NSColor(calibratedWhite: 0.72, alpha: 1)
                ).setFill()
                NSRect(x: x, y: y, width: min(square, rect.maxX - x), height: min(square, rect.maxY - y)).fill()
                x += square
                column += 1
            }
            y += square
            row += 1
        }
    }
}
