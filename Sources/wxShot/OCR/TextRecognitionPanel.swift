import AppKit

/// Cmd+C / Cmd+A inside an LSUIElement app: there is no main menu, so route them through the responder chain.
final class PanelTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// "Extract text" result window: recognizes text with Apple Vision (fully offline) and lets the user copy it.
final class TextRecognitionPanel: NSPanel {
    private static var current: TextRecognitionPanel?

    private let screenshot: NSImage
    private let textView = PanelTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var ocrTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var recognizedText = ""
    private let translates: Bool
    private var translationProvider: TranslationSessionProviding?

    /// `translate: true` runs the recognized text through on-device translation into the system language.
    static func present(image: NSImage, anchorRect: NSRect, screen: NSScreen, translate: Bool = false) {
        current?.close()
        if translate, TranslationBridge.makeProvider() == nil {
            ToastWindow.show(message: L10n.wxTranslateUnsupported, on: screen, duration: 3.0)
            return
        }
        let panel = TextRecognitionPanel(image: image, anchorRect: anchorRect, screen: screen, translate: translate)
        current = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.startRecognition()
    }

    private init(image: NSImage, anchorRect: NSRect, screen: NSScreen, translate: Bool) {
        screenshot = image
        translates = translate
        let size = NSSize(width: 400, height: 300)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = translate ? L10n.wxTranslateHeader : L10n.ocrTextHeader
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        level = .floating
        hidesOnDeactivate = false
        setFrameOrigin(Self.origin(for: size, anchorRect: anchorRect, screen: screen))
        buildContent(size: size)
        installMonitors()
    }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        ocrTask?.cancel()
        translationProvider?.cancel()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if Self.current === self { Self.current = nil }
        super.close()
    }

    // MARK: Layout

    private static func origin(for size: NSSize, anchorRect: NSRect, screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        var x = anchorRect.midX - size.width / 2
        var y = anchorRect.minY - size.height - 12
        if y < visible.minY { y = min(anchorRect.maxY + 12, visible.maxY - size.height) }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func buildContent(size: NSSize) {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        contentView = effect

        statusLabel.stringValue = L10n.ocrRecognizing
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        copyButton.title = L10n.ocrCopy
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.target = self
        copyButton.action = #selector(copyAll)
        copyButton.isEnabled = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(scroll)
        effect.addSubview(statusLabel)
        effect.addSubview(copyButton)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 36),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),
            copyButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            copyButton.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
            statusLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            statusLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
        ])
    }

    // MARK: Behavior

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, event.keyCode == 53 else { return event }
            self.close()
            return nil
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
    }

    private func startRecognition() {
        let image = screenshot
        ocrTask = Task { [weak self] in
            let text = await OCRService.recognize(image: image)
            guard !Task.isCancelled else { return }
            if await self?.translates == true, !text.isEmpty {
                await self?.translateAndShow(text)
            } else {
                await MainActor.run { self?.showResult(text) }
            }
        }
    }

    @MainActor
    private func translateAndShow(_ text: String) async {
        statusLabel.stringValue = L10n.wxTranslating
        guard let provider = TranslationBridge.makeProvider(), let host = contentView else {
            showResult("")
            return
        }
        translationProvider = provider
        // The SwiftUI bridge only runs while its view sits in a window.
        provider.hostView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        host.addSubview(provider.hostView)
        do {
            let translated = try await provider.translate(text: text, targetIdentifier: TranslationBridge.targetIdentifier)
            showResult(translated)
        } catch is CancellationError {
            return
        } catch {
            statusLabel.stringValue = L10n.wxTranslateFailed
        }
    }

    private func showResult(_ text: String) {
        recognizedText = text
        if text.isEmpty {
            statusLabel.stringValue = L10n.ocrNoText
            return
        }
        statusLabel.stringValue = ""
        textView.string = text
        copyButton.isEnabled = true
        makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    @objc private func copyAll() {
        guard !recognizedText.isEmpty else { return }
        let selected = textView.selectedRange()
        let text = selected.length > 0
            ? (textView.string as NSString).substring(with: selected)
            : recognizedText
        ClipboardManager.copyToClipboard(text: text)
        let screen = self.screen
        close()
        ToastWindow.show(message: L10n.ocrCopied, on: screen)
    }
}
