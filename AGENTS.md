# wxShot

Menu-bar-less macOS screenshot tool that replaces WeChat's screenshot when WeChat is not signed in. Pure AppKit, SwiftPM, no third-party code except the
vendored PermissionFlow.

## Build and verify
- `swift build` / `swift test` for development. `scripts/build.sh` builds `dist/wxShot.app` (ad-hoc signed).
- Release: `scripts/build.sh --universal --sign "Developer ID Application: …" --dmg --notarize` (keychain profile `MY_NTFSTOOL`).
- Mac App Store: `scripts/build.sh --mas …` (sandboxed, `MAS` compile flag removes self-update).
- Debug-only: `WXSHOT_DEBUG_CAPTURE=1 .build/debug/wxShot` opens the capture overlay at launch; `WXSHOT_TELEMETRY=0` turns reporting off.

## Product rules
- Free, no upload code, no network except the survival report (`Telemetry/SurvivalReporter.swift`, a handful of events per install) and the update check (non-MAS), which reads `https://ntfstool.com/wxshot-version.json` (source: `ntfstool.com/wxshot-version.json`, bump `version` on every release; set `min_version` to force an update); feedback goes through the user's mail app, no server.
- Default shortcut ⌥A. The shortcut is registered only while `WeChatMonitor.shouldOwnShortcut()` is true.
- Only Screen Recording permission is required. Do not add Accessibility or Input Monitoring requirements.
- New user-facing strings go through `scripts/add_strings.py` (8 languages) and `Utilities/L10n+wxShot.swift`.
- Keep the editor toolbar in `ToolbarLayout.default` aligned with WeChat's (plus a ··· more menu and a settings gear at the far right; icons are hand-drawn in `Editor/ToolbarIcons.swift`); `ToolbarView.groupEnds` draws the separators.
- Translate uses Apple on-device Translation (macOS 15+, `OCR/TranslationBridge.swift`); share uses the system share sheet.
- Maintenance budget is tiny: do not add features. Only fix macOS compatibility breaks.
