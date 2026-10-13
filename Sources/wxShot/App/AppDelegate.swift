import AppKit

/// wxShot lives in the background: no Dock icon, no menu bar icon by default. The screenshot shortcut works as soon as
/// the app is running, and launching the app again opens Settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var overlayController: OverlayWindowController?
    private var suspendedEditDraft: OverlayWindowController.SuspendedEditDraft?
    private var pendingReopenSettingsWorkItem: DispatchWorkItem?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would register the same shortcut and open a second, empty lens next to the first.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }
        ImageEditLauncher.clearTempDir()
        #if !MAS
        UpdateChecker.shared.checkAtLaunchIfDue()
        #endif
        if AppPermissions.screenRecordingGranted {
            OverlayWindowController.prewarmPresentationSurfaces()
            ScreenSnapshotProvider.shared.prewarm()
        }

        SettingsWindowController.shared.onMenuBarToggle = { [weak self] visible in
            self?.statusBarController?.setMenuBarVisible(visible)
        }
        statusBarController = StatusBarController(
            onTakeScreenshot: { [weak self] in self?.handleTrigger() },
            onTakeFullScreenScreenshot: { [weak self] in self?.handleFullScreenScreenshotTrigger() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        statusBarController?.setMenuBarVisible(Defaults.showMenuBar)

        for name in [Notification.Name.hotkeyDidChange, .weChatStateDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.applyHotkeyState()
            }
        }
        WeChatMonitor.shared.start()
        SurvivalReporter.shared.start()
        applyHotkeyState()

        #if DEBUG
        if DebugSnapshots.runIfRequested() { return }
        if ProcessInfo.processInfo.environment["WXSHOT_DEBUG_CAPTURE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.handleTrigger() }
            return
        }
        #endif
        if !Defaults.onboardingCompleted || !AppPermissions.screenRecordingGranted {
            OnboardingWindowController.shared.show()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        overlayController?.screenParametersDidChange()
        let displayIDs = Set(NSScreen.screens.compactMap { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        })
        ScreenSnapshotProvider.shared.invalidateAndPrewarm(displayIDs: displayIDs)
        OverlayWindowController.invalidateAndPrewarmPresentationSurfaces()
    }

    /// Opening the app again (Launchpad, Spotlight, double-click) is the way to reach Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        scheduleSettingsOpenFromReopen()
        return false
    }

    // MARK: - Hotkeys

    /// Registers the screenshot shortcut only while wxShot is supposed to own it (see `WeChatMonitor.shouldOwnShortcut`).
    private func applyHotkeyState() {
        let hotkeys = HotkeyManager.shared
        if hotkeys.isRecording {
            hotkeys.unregister()
            hotkeys.unregisterQuickPin()
            hotkeys.unregisterFullScreenScreenshot()
            return
        }

        if WeChatMonitor.shared.shouldOwnShortcut() {
            hotkeys.register { [weak self] context in
                guard let self else {
                    context.finish(.ignored)
                    return
                }
                self.handleTrigger(fromShortcut: true, triggerContext: context)
            }
        } else {
            hotkeys.unregister()
        }

        if Defaults.hasCustomQuickPinHotkey {
            hotkeys.registerQuickPin { [weak self] in self?.handleQuickPinTrigger() }
        } else {
            hotkeys.unregisterQuickPin()
        }
        if Defaults.hasCustomFullScreenScreenshotHotkey {
            hotkeys.registerFullScreenScreenshot { [weak self] in
                self?.handleFullScreenScreenshotTrigger(fromShortcut: true)
            }
        } else {
            hotkeys.unregisterFullScreenScreenshot()
        }
    }

    // MARK: - Capture

    func handleTrigger(
        fromShortcut: Bool = false,
        triggerContext: CaptureTriggerContext? = nil
    ) {
        let context = triggerContext ?? CaptureTriggerContext(
            source: fromShortcut ? .keyboardShortcut : .programmatic
        )
        context.mark(.handleTrigger)

        guard overlayController == nil else {
            context.finish(.ignored)
            return
        }
        guard AppPermissions.screenRecordingGranted else {
            context.finish(.ignored)
            OnboardingWindowController.shared.show()
            return
        }
        if resumeSuspendedEditIfAvailable() {
            context.finish(.rerouted)
            return
        }
        startCapture(
            triggerContext: context,
            onFirstFramePresented: fromShortcut ? {
                #if !MAS
                UpdateChecker.shared.checkFromScreenshotShortcutIfDue()
                #endif
            } : nil
        )
    }

    /// Select a screen region and pin it immediately after capture.
    func handleQuickPinTrigger() {
        guard overlayController == nil, AppPermissions.screenRecordingGranted else { return }
        startCapture(postCaptureAction: .quickPin)
    }

    func handleFullScreenScreenshotTrigger(fromShortcut: Bool = false) {
        guard overlayController == nil else { return }
        guard AppPermissions.screenRecordingGranted else {
            OnboardingWindowController.shared.show()
            return
        }

        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        let cursorPoint = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let image = ScreenCapturer.capture(rect: CGDisplayBounds(displayID), screen: screen),
              let controller = ImageEditLauncher.launch(
                generatedImage: image,
                source: .fullScreen,
                onRequestFocusReturn: { focusRestorer.restore() },
                onSuspend: { [weak self] draft in self?.handleEditSuspension(draft) },
                onComplete: { [weak self] finalImage in self?.handleEditCompletion(finalImage) }
              )
        else {
            ToastWindow.show(message: L10n.fullScreenScreenshotFailed)
            return
        }

        overlayController = controller
        applyHotkeyState()
    }

    /// Re-opens the editor for an image that was pinned (the pin toolbar's edit button).
    @discardableResult
    func handlePinnedImageEditRequest(_ image: NSImage, beforePresent: () -> Void) -> Bool {
        guard overlayController == nil else { return false }
        beforePresent()

        guard let controller = ImageEditLauncher.launch(
            generatedImage: image,
            source: .pin,
            keepsEditorAcrossSpaces: Defaults.pinAcrossSpaces,
            onSuspend: { [weak self] draft in self?.handleEditSuspension(draft) },
            onComplete: { [weak self] finalImage in self?.handleEditCompletion(finalImage) }
        ) else {
            return false
        }

        overlayController = controller
        applyHotkeyState()
        return true
    }

    func startCapture(
        postCaptureAction: OverlayWindowController.PostCaptureAction = .edit,
        triggerContext: CaptureTriggerContext? = nil,
        onFirstFramePresented: (() -> Void)? = nil
    ) {
        let context = triggerContext ?? CaptureTriggerContext(source: .programmatic)
        context.mark(.startCapture)
        guard overlayController == nil else {
            context.finish(.ignored)
            return
        }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        overlayController = OverlayWindowController(
            postCaptureAction: postCaptureAction,
            triggerContext: context,
            onFirstFramePresented: onFirstFramePresented,
            onRequestFocusReturn: { focusRestorer.restore() },
            onSuspend: { [weak self] draft in self?.handleEditSuspension(draft) },
            onComplete: { [weak self] finalImage in self?.handleEditCompletion(finalImage) }
        )
        overlayController?.activate()
        applyHotkeyState()
    }

    private func handleEditCompletion(_ finalImage: NSImage?) {
        if let finalImage = finalImage {
            SurvivalReporter.shared.count("capture")
            let quality = Defaults.screenshotClipboardQuality
            if quality.usesLossyCompression {
                ToastWindow.show(message: L10n.screenshotQualityCompressingClipboard, duration: 600)
            }
            ImageOutputEncoder.encodeClipboardAsync(image: finalImage, quality: quality) { result in
                if quality.usesLossyCompression {
                    ToastWindow.dismiss()
                }
                switch result {
                case .failure:
                    ToastWindow.show(message: L10n.screenshotCompressionFailed, duration: 3.0)
                case .success(let output):
                    ClipboardManager.copyToClipboard(imageOutput: output)
                    ToastWindow.show()
                }
            }
        }
        overlayController = nil
        applyHotkeyState()
    }

    private func handleEditSuspension(_ draft: OverlayWindowController.SuspendedEditDraft) {
        suspendedEditDraft = draft
        overlayController = nil
        applyHotkeyState()
        ToastWindow.show(
            message: L10n.editSuspendedToast,
            on: screen(for: draft),
            duration: 3.0
        )
    }

    private func resumeSuspendedEditIfAvailable() -> Bool {
        guard let draft = suspendedEditDraft else { return false }
        let focusRestorer = SourceAppFocusRestorer.captureFrontmostApplication()
        let controller = OverlayWindowController(
            suspendedDraft: draft,
            onRequestFocusReturn: { focusRestorer.restore() },
            onSuspend: { [weak self] draft in self?.handleEditSuspension(draft) },
            onComplete: { [weak self] finalImage in self?.handleEditCompletion(finalImage) }
        )
        suspendedEditDraft = nil
        overlayController = controller
        controller.activate()
        applyHotkeyState()
        return true
    }

    private func screen(for draft: OverlayWindowController.SuspendedEditDraft) -> NSScreen? {
        if let displayID = draft.screenDisplayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
           }) {
            return screen
        }
        return NSScreen.screens.first(where: { $0.frame == draft.screenFrame }) ?? NSScreen.main
    }

    // MARK: - Settings

    private func openSettings() {
        SettingsWindowController.shared.showAsSettings()
    }

    private func scheduleSettingsOpenFromReopen() {
        pendingReopenSettingsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.overlayController == nil else { return }
            if OnboardingWindowController.shared.isVisible { return }
            self.openSettings()
        }
        pendingReopenSettingsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }
}
