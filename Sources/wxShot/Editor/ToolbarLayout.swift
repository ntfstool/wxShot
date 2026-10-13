import AppKit

/// Stable identifier for every button that can appear in the editor's
/// toolbars. Raw values are persisted in `UserDefaults`, so existing cases
/// must never be renamed — only added or deprecated.
enum ToolbarItemID: String, Codable, CaseIterable {
    // Annotation tools (toggle an `EditTool`)
    case rectangle
    case ellipse
    case arrow
    case line
    case pen
    case marker
    case spotlight
    case mosaic
    case eraser
    case magnifier
    case numbered
    case text
    case qrCode
    case emoji
    case insertImage
    // Stateful actions
    case colorPicker
    case undo
    case redo
    case moveSelection
    case scrollCapture
    case rotate
    case beautify
    case ocr
    case screenshotTranslate
    // Output actions
    case save
    case upload
    case pin
    case record
    case close
    case confirm
    case settings
    case share
    case more
}

extension ToolbarItemID {
    /// How the button behaves — drives which `on*` callback it fires and
    /// whether it carries a persistent selected/active state.
    enum Kind {
        /// Annotation tool — selecting it toggles an `EditTool`.
        case toggleTool
        /// Has an on/off state but is not an `EditTool` (scroll capture, beautify).
        case toggleAction
        /// Fires once on click, no persistent state.
        case momentary
        /// Press-and-drag handle (move selection) — not a tappable button.
        case dragHandle
    }

    var kind: Kind {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pen, .marker, .spotlight, .mosaic, .eraser, .magnifier, .numbered, .text, .emoji:
            return .toggleTool
        case .scrollCapture, .rotate, .beautify, .qrCode:
            return .toggleAction
        case .moveSelection:
            return .dragHandle
        case .insertImage, .colorPicker, .undo, .redo, .ocr, .screenshotTranslate, .save, .upload, .pin, .record, .close, .confirm, .settings, .share, .more:
            return .momentary
        }
    }

    /// The annotation tool a `toggleTool` item maps to; `nil` for all others.
    var editTool: EditTool? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse:   return .ellipse
        case .arrow:     return .arrow
        case .line:      return .line
        case .pen:       return .pen
        case .marker:    return .marker
        case .spotlight: return .spotlight
        case .mosaic:    return .mosaic
        case .eraser:    return .eraser
        case .magnifier: return .magnifier
        case .numbered:  return .numbered
        case .text:      return .text
        case .emoji:     return .emoji
        default:         return nil
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle:     return "rectangle"
        case .ellipse:       return "circle"
        case .arrow:         return "arrow.up.right"
        case .line:          return "line.diagonal"
        case .pen:           return "pencil"
        case .marker:        return "highlighter"
        case .spotlight:     return "rectangle.inset.filled"
        case .mosaic:        return "square.grid.3x3"
        case .eraser:        return "eraser"
        case .magnifier:     return "plus.magnifyingglass"
        case .numbered:      return "1.circle"
        case .text:          return "textformat"
        case .qrCode:        return "qrcode.viewfinder"
        case .emoji:         return "face.smiling"
        case .insertImage:   return "photo"
        case .colorPicker:   return "eyedropper"
        case .undo:          return "arrow.uturn.backward"
        case .redo:          return "arrow.uturn.forward"
        case .moveSelection: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scrollCapture: return "arrow.up.and.down.text.horizontal"
        case .rotate:        return "rotate.left"
        case .beautify:      return "sparkles"
        case .ocr:           return "text.viewfinder"
        case .screenshotTranslate: return "translate"
        case .save:          return "square.and.arrow.down"
        case .upload:        return "icloud.and.arrow.up"
        case .pin:           return "pin"
        case .record:        return "record.circle"
        case .close:         return "xmark"
        case .confirm:       return "checkmark"
        case .settings:      return "gearshape"
        case .share:         return "arrowshape.turn.up.right"
        case .more:          return "ellipsis"
        }
    }

    /// Keep the OCR symbol's Chinese glyph fixed regardless of the system locale.
    func iconImage(pointSize: CGFloat) -> NSImage? {
        if let drawn = ToolbarIcons.image(for: self) { return drawn }
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize + 1, weight: self == .settings ? .light : .medium)
        let locale: Locale? = switch self {
        case .ocr: Locale(identifier: "zh-Hans")
        case .text: Locale(identifier: "en")
        default: nil
        }
        return (locale.map { base.withLocale($0) } ?? base).withSymbolConfiguration(config)
    }

    var localizedTitle: String {
        switch self {
        case .rectangle:     return L10n.tipRectangle
        case .ellipse:       return L10n.tipEllipse
        case .arrow:         return L10n.tipArrow
        case .line:          return L10n.tipLine
        case .pen:           return L10n.tipPen
        case .marker:        return L10n.tipMarker
        case .spotlight:     return L10n.tipSpotlight
        case .mosaic:        return L10n.tipMosaic
        case .eraser:        return L10n.tipEraser
        case .magnifier:     return L10n.tipMagnifier
        case .numbered:      return L10n.tipNumbered
        case .text:          return L10n.tipText
        case .qrCode:        return L10n.tipQRCode
        case .emoji:         return L10n.tipEmoji
        case .insertImage:   return L10n.tipInsertImage
        case .colorPicker:   return L10n.tipColorPicker
        case .undo:          return L10n.tipUndo
        case .redo:          return L10n.tipRedo
        case .moveSelection: return L10n.tipMoveSelection
        case .scrollCapture: return L10n.tipScrollCapture
        case .rotate:        return L10n.tipRotate
        case .beautify:      return L10n.tipBeautify
        case .ocr:           return L10n.tipOCR
        case .screenshotTranslate: return L10n.tipScreenshotTranslate
        case .save:          return L10n.tipSave
        case .upload:        return L10n.tipUpload
        case .pin:           return L10n.tipPin
        case .record:        return L10n.tipRecord
        case .close:         return L10n.tipCancel
        case .confirm:       return L10n.tipConfirm
        case .settings:      return L10n.wxTipSettings
        case .share:         return L10n.wxTipShare
        case .more:          return L10n.wxTipMore
        }
    }

    /// Localized hover-tooltip text with the current configured shortcut.
    var tooltip: String {
        guard let shortcut = editorShortcutDisplay else { return localizedTitle }
        return "\(localizedTitle) (\(shortcut))"
    }

    var editorShortcutDisplay: String? {
        guard supportsEditorShortcut else { return nil }
        return EditorShortcutRegistry.displayString(for: .toolbar(self))
    }

    /// Icon tint in the resting state.
    var normalColor: NSColor {
        switch self {
        case .close:   return toolbarDangerRed
        case .confirm: return toolbarConfirmGreen
        default:       return toolbarIconGray
        }
    }

    /// Icon tint while selected/active. For `momentary` items this equals
    /// `normalColor` — they never enter a selected state.
    var selectedColor: NSColor {
        switch kind {
        case .toggleTool, .toggleAction:
            return toolbarConfirmGreen
        case .momentary, .dragHandle:
            return normalColor
        }
    }
}

/// Red used for the cancel button's icon. Mirrors the literal previously
/// inlined in `ToolbarView.setupButtons()`.
let toolbarDangerRed = NSColor(srgbRed: 0.89, green: 0.35, blue: 0.32, alpha: 1)
let toolbarConfirmGreen = NSColor(srgbRed: 0.24, green: 0.72, blue: 0.42, alpha: 1)
let toolbarIconGray = NSColor(srgbRed: 0.353, green: 0.353, blue: 0.353, alpha: 1)

/// User-customizable assignment of every toolbar item to the primary
/// (horizontal) toolbar, the side (vertical) toolbar, or hidden.
struct ToolbarLayout: Equatable {
    var primary: [ToolbarItemID]
    var side: [ToolbarItemID]
    var hidden: [ToolbarItemID]

    /// Canonical left-to-right order. Used for the default layout and to
    /// place any newly-introduced tool that an older persisted layout never
    /// recorded.
    static let canonicalOrder: [ToolbarItemID] = [
        .rectangle, .ellipse, .line, .arrow, .pen, .marker, .spotlight, .mosaic, .eraser, .numbered, .text, .emoji, .insertImage,
        .colorPicker, .magnifier, .undo, .redo, .moveSelection, .scrollCapture, .rotate, .beautify, .qrCode, .ocr,
        .screenshotTranslate,
        .save, .upload, .pin, .record, .close, .confirm, .settings, .share, .more,
    ]

    /// wxShot's fixed layout, identical to WeChat's screenshot bar: rectangle, ellipse, emoji, arrow, pen, mosaic, text |
    /// translate, text extraction, long screenshot | undo, save, pin, share, close, confirm; then "more" and settings.
    /// Everything else lives in the "more" menu (`moreMenuItems`).
    static var `default`: ToolbarLayout {
        ToolbarLayout(
            primary: [
                .rectangle, .ellipse, .emoji, .arrow, .pen, .mosaic, .text,
                .screenshotTranslate, .ocr, .scrollCapture,
                .undo, .save, .pin, .share, .close, .confirm,
                .more, .settings,
            ],
            side: [],
            hidden: [
                .line, .marker, .spotlight, .eraser, .insertImage, .colorPicker, .magnifier, .numbered, .redo,
                .moveSelection, .rotate, .beautify, .qrCode, .upload, .record,
            ]
        )
    }

    /// Tools reachable from the "more" button, in menu order.
    static let moreMenuItems: [ToolbarItemID] = [
        .numbered, .redo, .line, .marker, .spotlight, .eraser, .magnifier, .rotate, .insertImage,
    ]

    /// Drops duplicate / unknown ids and slots any tool missing from all
    /// three buckets next to its canonical neighbour, so the result always
    /// covers every `ToolbarItemID` exactly once regardless of app-version
    /// drift. A newly-introduced tool lands beside its siblings (e.g. `line`
    /// after `ellipse`) instead of being dumped at the end of the bar.
    func normalized() -> ToolbarLayout {
        var seen = Set<ToolbarItemID>()
        func dedup(_ ids: [ToolbarItemID]) -> [ToolbarItemID] {
            ids.filter { seen.insert($0).inserted }
        }
        var p = dedup(primary)
        var s = dedup(side)
        var h = dedup(hidden)

        let missing = Self.canonicalOrder.filter { !seen.contains($0) }
        for item in missing {
            // Existing layouts put scroll capture on the side bar. Anchor the
            // new rotation action to Beautify so upgrading preserves its place.
            if item == .rotate {
                if let index = p.firstIndex(of: .beautify) {
                    p.insert(item, at: index)
                } else if let index = s.firstIndex(of: .beautify) {
                    s.insert(item, at: index)
                } else if let index = h.firstIndex(of: .beautify) {
                    h.insert(item, at: index)
                } else {
                    p.append(item)
                }
                seen.insert(item)
                continue
            }
            guard let canonicalIdx = Self.canonicalOrder.firstIndex(of: item) else { continue }
            // Walk back through the canonical order to the nearest sibling
            // that's already placed, then drop the new tool right after it
            // in whichever bucket that sibling lives in.
            var placed = false
            for prevIdx in stride(from: canonicalIdx - 1, through: 0, by: -1) {
                let prev = Self.canonicalOrder[prevIdx]
                if let i = p.firstIndex(of: prev) { p.insert(item, at: i + 1); placed = true; break }
                if let i = s.firstIndex(of: prev) { s.insert(item, at: i + 1); placed = true; break }
                if let i = h.firstIndex(of: prev) { h.insert(item, at: i + 1); placed = true; break }
            }
            if !placed { p.insert(item, at: 0) }
            seen.insert(item)
        }
        return ToolbarLayout(primary: p, side: s, hidden: h)
    }
}

extension ToolbarLayout {
    /// Builds a layout from a persisted `[bucket: [rawValue]]` dictionary,
    /// silently skipping any raw value no longer backed by a `ToolbarItemID`.
    init(dictionary: [String: [String]]) {
        func parse(_ key: String) -> [ToolbarItemID] {
            (dictionary[key] ?? []).compactMap(ToolbarItemID.init(rawValue:))
        }
        self.init(
            primary: parse("primary"),
            side: parse("side"),
            hidden: parse("hidden")
        )
    }

    /// Plain `[String: [String]]` form suitable for `UserDefaults`.
    var dictionary: [String: [String]] {
        [
            "primary": primary.map(\.rawValue),
            "side": side.map(\.rawValue),
            "hidden": hidden.map(\.rawValue),
        ]
    }
}

extension Defaults {
    /// wxShot ships one fixed toolbar that mirrors WeChat's, so there is nothing to persist.
    static var toolbarLayout: ToolbarLayout { .default }
}
