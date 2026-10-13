#!/usr/bin/env swift
// 用法: swift make_icon.swift <SF Symbol 名> <#RRGGBB> <输出.icns>
// 用 product.json 里的 iconSymbol/iconColor 自动生成一个统一风格的 macOS 图标（渐变圆角方块 + 白色符号）。
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: make_icon.swift <symbol> <#RRGGBB> <out.icns>"); exit(2) }
let symbol = args[1], hex = args[2], out = args[3]

func color(_ hex: String) -> NSColor {
    var h = hex; if h.hasPrefix("#") { h.removeFirst() }
    let v = UInt32(h, radix: 16) ?? 0x34C759
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.098                       // macOS 图标网格留白
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
    let base = color(hex)
    // 背景与系统「信息」图标一致：自上而下的绿色渐变（取自 Messages.app 图标像素）。
    let top = hex == "messages" ? color("#61F082") : (base.blended(withFraction: 0.25, of: .white) ?? base)
    let bottom = hex == "messages" ? color("#00C73E") : (base.blended(withFraction: 0.25, of: .black) ?? base)
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = img.size
        img.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = NSTemporaryDirectory() + "mx-\(UUID().uuidString).iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", out]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
exit(p.terminationStatus)
