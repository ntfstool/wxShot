import AppKit

/// Hand-drawn line icons for the editor toolbar: 1.7-unit strokes with round caps on a 24-unit grid, drawn in black
/// so `ToolButton` can tint them. Proportions follow the WeChat screenshot bar.
enum ToolbarIcons {
    static let side: CGFloat = 24
    private static let unit: CGFloat = 24

    static func image(for id: ToolbarItemID) -> NSImage? {
        guard let draw = drawer(for: id) else { return nil }
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: true) { _ in
            let scale = side / unit
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            NSColor.black.set()
            draw()
            return true
        }
    }

    // MARK: Helpers (coordinates are top-left origin, the image is flipped)

    private static func stroke(_ path: NSBezierPath, width: CGFloat = 1.7) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func line(_ points: [(CGFloat, CGFloat)], close: Bool = false) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { path.line(to: NSPoint(x: p.0, y: p.1)) }
        if close { path.close() }
        return path
    }

    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 2) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    /// The 文 glyph used by translate and text extraction.
    private static func wen(cx: CGFloat, cy: CGFloat, s: CGFloat, width: CGFloat) {
        stroke(line([(cx - s * 0.5, cy - s * 0.55), (cx + s * 0.5, cy - s * 0.55)]), width: width)
        stroke(line([(cx, cy - s * 0.95), (cx, cy - s * 0.55)]), width: width)
        stroke(line([(cx - s * 0.45, cy - s * 0.35), (cx + s * 0.45, cy + s * 0.8)]), width: width)
        stroke(line([(cx + s * 0.45, cy - s * 0.35), (cx - s * 0.45, cy + s * 0.8)]), width: width)
    }

    private static func corners(inset: CGFloat, length: CGFloat) -> NSBezierPath {
        let a = inset, b = unit - inset, l = length
        let path = NSBezierPath()
        for (x, y, dx, dy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            path.move(to: NSPoint(x: x + dx * l, y: y))
            path.line(to: NSPoint(x: x + dx * 1.5, y: y))
            path.curve(to: NSPoint(x: x, y: y + dy * 1.5), controlPoint1: NSPoint(x: x + dx * 0.4, y: y), controlPoint2: NSPoint(x: x, y: y + dy * 0.4))
            path.line(to: NSPoint(x: x, y: y + dy * l))
        }
        return path
    }

    // MARK: Drawings

    private static func drawer(for id: ToolbarItemID) -> (() -> Void)? {
        switch id {
        case .rectangle:
            return { stroke(box(2.5, 4.5, 19, 15, r: 2.2)) }
        case .ellipse:
            return { stroke(NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 18, height: 18))) }
        case .emoji:
            return {
                stroke(NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 18, height: 18)))
                for x in [9.0, 15.0] as [CGFloat] { NSBezierPath(ovalIn: NSRect(x: x - 1.1, y: 8.9, width: 2.2, height: 2.2)).fill() }
                let mouth = NSBezierPath()
                mouth.move(to: NSPoint(x: 7.8, y: 13.6))
                mouth.line(to: NSPoint(x: 16.2, y: 13.6))
                mouth.curve(to: NSPoint(x: 7.8, y: 13.6), controlPoint1: NSPoint(x: 15.5, y: 19), controlPoint2: NSPoint(x: 8.5, y: 19))
                stroke(mouth, width: 1.5)
            }
        case .arrow:
            return {
                stroke(line([(5.5, 18.5), (18.5, 5.5)]))
                stroke(line([(9.5, 5.5), (18.5, 5.5), (18.5, 14.5)]))
            }
        case .pen:
            return {
                let body = NSBezierPath()
                body.move(to: NSPoint(x: 4, y: 20))
                body.line(to: NSPoint(x: 5.2, y: 15.4))
                body.line(to: NSPoint(x: 15.6, y: 5))
                body.curve(to: NSPoint(x: 18.6, y: 5), controlPoint1: NSPoint(x: 16.4, y: 4.2), controlPoint2: NSPoint(x: 17.8, y: 4.2))
                body.line(to: NSPoint(x: 19.4, y: 5.8))
                body.curve(to: NSPoint(x: 19.4, y: 8.8), controlPoint1: NSPoint(x: 20.2, y: 6.6), controlPoint2: NSPoint(x: 20.2, y: 8))
                body.line(to: NSPoint(x: 8.6, y: 19.2))
                body.close()
                stroke(body)
                stroke(line([(14, 6.8), (17.2, 10)]), width: 1.5)
            }
        case .mosaic:
            return {
                stroke(box(3, 3, 18, 18, r: 1.8))
                let cell: CGFloat = 2.4
                for row in 0..<5 {
                    for col in 0..<5 where (row + col) % 2 == 0 {
                        NSRect(x: 6 + CGFloat(col) * cell, y: 6 + CGFloat(row) * cell, width: cell, height: cell).fill()
                    }
                }
            }
        case .text:
            return {
                stroke(box(3, 3, 18, 18, r: 2))
                stroke(line([(7.5, 8), (16.5, 8)]))
                stroke(line([(12, 8), (12, 17)]))
            }
        case .screenshotTranslate:
            return {
                let back = NSBezierPath()
                back.move(to: NSPoint(x: 11, y: 11))
                back.line(to: NSPoint(x: 11, y: 4.6))
                back.curve(to: NSPoint(x: 12.6, y: 3), controlPoint1: NSPoint(x: 11, y: 3.7), controlPoint2: NSPoint(x: 11.7, y: 3))
                back.line(to: NSPoint(x: 19.4, y: 3))
                back.curve(to: NSPoint(x: 21, y: 4.6), controlPoint1: NSPoint(x: 20.3, y: 3), controlPoint2: NSPoint(x: 21, y: 3.7))
                back.line(to: NSPoint(x: 21, y: 11.4))
                back.curve(to: NSPoint(x: 19.4, y: 13), controlPoint1: NSPoint(x: 21, y: 12.3), controlPoint2: NSPoint(x: 20.3, y: 13))
                back.line(to: NSPoint(x: 13, y: 13))
                stroke(back)
                stroke(line([(14.4, 10.2), (16, 5.8), (17.6, 10.2)]), width: 1.4)
                stroke(line([(14.9, 8.8), (17.1, 8.8)]), width: 1.4)
                stroke(box(3, 11, 10, 10, r: 1.6))
                wen(cx: 8, cy: 16.2, s: 3.6, width: 1.3)
            }
        case .ocr:
            return {
                stroke(corners(inset: 3, length: 6))
                wen(cx: 12, cy: 12.3, s: 6.6, width: 1.6)
            }
        case .scrollCapture:
            return {
                let frame = box(4.5, 2.5, 15, 19, r: 2)
                frame.setLineDash([2.3, 2.3], count: 2, phase: 0)
                stroke(frame, width: 1.5)
                stroke(line([(12, 7), (12, 17)]))
                stroke(line([(9.4, 9.6), (12, 7), (14.6, 9.6)]))
                stroke(line([(9.4, 14.4), (12, 17), (14.6, 14.4)]))
            }
        case .undo, .redo:
            let flip = id == .redo
            return {
                if flip {
                    NSGraphicsContext.current?.cgContext.translateBy(x: unit, y: 0)
                    NSGraphicsContext.current?.cgContext.scaleBy(x: -1, y: 1)
                }
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 9.5, y: 6))
                path.line(to: NSPoint(x: 5, y: 10.5))
                path.line(to: NSPoint(x: 9.5, y: 15))
                stroke(path)
                let tail = NSBezierPath()
                tail.move(to: NSPoint(x: 5, y: 10.5))
                tail.line(to: NSPoint(x: 14.5, y: 10.5))
                tail.curve(to: NSPoint(x: 14.5, y: 18), controlPoint1: NSPoint(x: 19.5, y: 10.5), controlPoint2: NSPoint(x: 19.5, y: 18))
                tail.line(to: NSPoint(x: 4, y: 18))
                stroke(tail)
            }
        case .save:
            return {
                let tray = NSBezierPath()
                tray.move(to: NSPoint(x: 8, y: 6.5))
                tray.line(to: NSPoint(x: 5.6, y: 6.5))
                tray.curve(to: NSPoint(x: 4, y: 8.1), controlPoint1: NSPoint(x: 4.7, y: 6.5), controlPoint2: NSPoint(x: 4, y: 7.2))
                tray.line(to: NSPoint(x: 4, y: 19.4))
                tray.curve(to: NSPoint(x: 5.6, y: 21), controlPoint1: NSPoint(x: 4, y: 20.3), controlPoint2: NSPoint(x: 4.7, y: 21))
                tray.line(to: NSPoint(x: 18.4, y: 21))
                tray.curve(to: NSPoint(x: 20, y: 19.4), controlPoint1: NSPoint(x: 19.3, y: 21), controlPoint2: NSPoint(x: 20, y: 20.3))
                tray.line(to: NSPoint(x: 20, y: 8.1))
                tray.curve(to: NSPoint(x: 18.4, y: 6.5), controlPoint1: NSPoint(x: 20, y: 7.2), controlPoint2: NSPoint(x: 19.3, y: 6.5))
                tray.line(to: NSPoint(x: 16, y: 6.5))
                stroke(tray)
                stroke(line([(12, 3), (12, 14.5)]))
                stroke(line([(8.4, 11), (12, 14.5), (15.6, 11)]))
            }
        case .pin:
            return {
                stroke(line([(8.5, 3.5), (15.5, 3.5)]))
                stroke(line([(10, 3.5), (10, 9.5), (7, 13.5), (17, 13.5), (14, 9.5), (14, 3.5)], close: false))
                stroke(line([(12, 13.5), (12, 21)]))
            }
        case .share:
            return {
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: 14, y: 4.5))
                arrow.line(to: NSPoint(x: 21, y: 10.3))
                arrow.line(to: NSPoint(x: 14, y: 16))
                arrow.line(to: NSPoint(x: 14, y: 12.6))
                arrow.curve(to: NSPoint(x: 4, y: 19.5), controlPoint1: NSPoint(x: 8.8, y: 12.2), controlPoint2: NSPoint(x: 5.4, y: 14.6))
                arrow.curve(to: NSPoint(x: 14, y: 8), controlPoint1: NSPoint(x: 4.6, y: 12.4), controlPoint2: NSPoint(x: 8.4, y: 8))
                arrow.close()
                stroke(arrow)
            }
        case .close:
            return { stroke(line([(5.5, 5.5), (18.5, 18.5)]), width: 1.9); stroke(line([(18.5, 5.5), (5.5, 18.5)]), width: 1.9) }
        case .confirm:
            return { stroke(line([(3.5, 12.5), (9.5, 18.5), (20.5, 6)]), width: 1.9) }
        case .more:
            return { for x in [5.0, 12.0, 19.0] as [CGFloat] { NSBezierPath(ovalIn: NSRect(x: x - 1.7, y: 10.3, width: 3.4, height: 3.4)).fill() } }
        default:
            return nil
        }
    }
}
