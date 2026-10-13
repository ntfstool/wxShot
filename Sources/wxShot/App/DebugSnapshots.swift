#if DEBUG
import AppKit

/// `WXSHOT_SNAPSHOT=<dir> [WXSHOT_LANG=zh|en|…] .build/debug/wxShot` renders real windows and the real toolbar to PNG
/// (no Screen Recording permission needed) for the website, then quits.
enum DebugSnapshots {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["WXSHOT_SNAPSHOT"] else { return false }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if let raw = ProcessInfo.processInfo.environment["WXSHOT_LANG"], let lang = AppLanguage(rawValue: raw) {
            Defaults.language = lang
        }
        let tag = Defaults.language.lprojName
        DispatchQueue.main.async {
            for (name, controller) in [("settings", SettingsWindowController.shared as NSWindowController),
                                       ("onboarding", OnboardingWindowController.shared as NSWindowController)] {
                controller.window?.orderFrontRegardless()
                if let view = controller.window?.contentView { write(view, to: out.appendingPathComponent("\(name)-\(tag).png")) }
            }
            for dark in [false, true] {
                write(toolbarScene(dark: dark), to: out.appendingPathComponent("toolbar-\(dark ? "dark" : "light").png"))
            }
            let lens = MagnifierLensPanelWindow()
            if let cg = lensTestImage() {
                lens.update(snapshot: cg, screenFrame: NSRect(x: 0, y: 0, width: 400, height: 300),
                            mouseLocation: NSPoint(x: 200, y: 150), format: .hex)
            }
            if let view = lens.contentView { write(view, to: out.appendingPathComponent("lens.png")) }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func toolbarScene(dark: Bool) -> NSView {
        let size = NSSize(width: 1000, height: 420)
        let scene = NSView(frame: NSRect(origin: .zero, size: size))
        scene.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        scene.wantsLayer = true
        scene.layer?.backgroundColor = (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).cgColor

        let selection = NSView(frame: NSRect(x: 170, y: 120, width: 660, height: 250))
        selection.wantsLayer = true
        selection.layer?.backgroundColor = (dark ? NSColor(white: 0.2, alpha: 1) : NSColor.white).cgColor
        selection.layer?.borderColor = NSColor.systemGreen.cgColor
        selection.layer?.borderWidth = 2
        scene.addSubview(selection)

        let toolbar = ToolbarView(items: ToolbarLayout.default.primary, orientation: .horizontal)
        toolbar.frame.origin = NSPoint(x: selection.frame.maxX - toolbar.frame.width, y: selection.frame.minY - toolbar.frame.height - 10)
        scene.addSubview(toolbar)
        return scene
    }

    private static func lensTestImage() -> CGImage? {
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { rect in
            NSColor(white: 0.985, alpha: 1).setFill(); rect.fill()
            NSColor.darkGray.setFill(); NSRect(x: 150, y: 100, width: 60, height: 60).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func write(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
