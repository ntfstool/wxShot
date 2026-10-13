import AppKit
import Foundation

/// Screenshot file names follow the macOS convention: `wxShot 2026-10-13 at 12.34.56.png`.
enum FilenameTemplate {
    static func imageFileName(
        for image: NSImage?,
        fileExtension: String = "png",
        imageSize: CGSize? = nil,
        date: Date = Date(),
        consumeCounters: Bool = true
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "wxShot \(formatter.string(from: date)).\(fileExtension)"
    }
}
