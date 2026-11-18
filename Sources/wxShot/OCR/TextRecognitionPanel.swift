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
    #if DEBUG
    static var debugContent: NSView? { current?.contentView }
    #endif

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
        let size = Self.panelSize(for: image.size, screen: screen)
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
        buildContent(size: size, stacked: Self.isWide(image.size))
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

    /// Wide screenshots (a web page row, a long sentence) go above the text
    /// instead of beside it, so the text column keeps a readable width.
    private static func isWide(_ imageSize: NSSize) -> Bool {
        imageSize.height > 0 && imageSize.width / imageSize.height > 1.6
    }

    /// Never larger than the visible screen; issue #1 had the panel run off
    /// the right edge on a 1920×1080 display.
    private static func panelSize(for imageSize: NSSize, screen: NSScreen) -> NSSize {
        let visible = screen.visibleFrame
        let wanted = isWide(imageSize) ? NSSize(width: 820, height: 600) : NSSize(width: 780, height: 440)
        return NSSize(width: min(wanted.width, visible.width - 16),
                      height: min(wanted.height, visible.height - 16))
    }

    private static func origin(for size: NSSize, anchorRect: NSRect, screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        var x = anchorRect.midX - size.width / 2
        var y = anchorRect.minY - size.height - 12
        if y < visible.minY { y = min(anchorRect.maxY + 12, visible.maxY - size.height) }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func buildContent(size: NSSize, stacked: Bool) {
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
        textView.font = .systemFont(ofSize: 15)
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

        // Left: the screenshot, so the text can be compared against it; right: the recognized text.
        let preview = NSImageView()
        preview.image = screenshot
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.imageAlignment = .alignCenter
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        // The image's own pixel size must not push the panel wider or taller.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            preview.setContentCompressionResistancePriority(.init(1), for: orientation)
            preview.setContentHuggingPriority(.init(1), for: orientation)
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(preview)
        effect.addSubview(divider)
        effect.addSubview(scroll)
        effect.addSubview(statusLabel)
        effect.addSubview(copyButton)
        var constraints = [
            copyButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            copyButton.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),
            preview.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            preview.topAnchor.constraint(equalTo: effect.topAnchor, constant: 40),
        ]
        if stacked {
            // Top: the screenshot; below: the text, full width.
            constraints += [
                preview.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
                preview.heightAnchor.constraint(equalTo: effect.heightAnchor, multiplier: 0.34),
                divider.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
                divider.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
                divider.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
                divider.heightAnchor.constraint(equalToConstant: 1),
                scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
                statusLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            ]
        } else {
            constraints += [
                preview.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14),
                preview.widthAnchor.constraint(equalTo: effect.widthAnchor, multiplier: 0.42),
                divider.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
                divider.topAnchor.constraint(equalTo: effect.topAnchor, constant: 40),
                divider.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14),
                divider.widthAnchor.constraint(equalToConstant: 1),
                scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 10),
                scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 40),
                statusLabel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 14),
            ]
        }
        constraints.append(statusLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor))
        NSLayoutConstraint.activate(constraints)
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
