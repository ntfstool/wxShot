import AppKit

final class OCRLineSelectionOverlayView: NSView {
    private struct TokenRef: Hashable {
        let lineIndex: Int
        let tokenIndex: Int
    }

    private let imageSize: NSSize
    var showsLineBoxes = false {
        didSet {
            if !showsLineBoxes {
                clearSelection()
            }
            needsDisplay = true
        }
    }
    var lines: [RecognizedTextLine] = [] {
        didSet {
            selectedTokenRefs = Set(selectedTokenRefs.filter { ref in
                lines.indices.contains(ref.lineIndex)
                    && lines[ref.lineIndex].tokens.indices.contains(ref.tokenIndex)
            })
            selectedLineIndices = Set(selectedLineIndices.filter { lines.indices.contains($0) })
            selectedText = selectedText(for: orderedSelectedTokenRefs())
            needsDisplay = true
        }
    }
    var onSelectText: ((String, [Int], Bool) -> Void)?

    private var selectedTokenRefs: Set<TokenRef> = [] {
        didSet {
            if oldValue != selectedTokenRefs {
                needsDisplay = true
            }
        }
    }
    private var selectedLineIndices: Set<Int> = []
    private var selectedText = ""
    private var selectionStartPoint: NSPoint?
    private var selectionStartTokenRef: TokenRef?
    private var selectionStartLineIndex: Int?

    init(imageSize: NSSize) {
        self.imageSize = imageSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsLineBoxes else { return }

        let imageRect = fittedImageRect()
        let copyableRects = lines.enumerated().flatMap { index, line in
            textBlockRects(for: index, line: line, in: imageRect)
        }
        guard !copyableRects.isEmpty else { return }

        drawDimMask(excluding: copyableRects)
        drawCopyableTextBackplates(copyableRects)

        for rect in selectedTextRects(in: imageRect) {
            drawSelectedTextRect(rect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard showsLineBoxes, !lines.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let imageRect = fittedImageRect()
        selectionStartPoint = point
        selectionStartTokenRef = tokenRef(at: point, in: imageRect)
        selectionStartLineIndex = selectionStartTokenRef == nil ? lineIndex(at: point, in: imageRect) : nil
        updateSelection(to: point, isFinal: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionStartPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateSelection(to: point, isFinal: false)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            selectionStartPoint = nil
            selectionStartTokenRef = nil
            selectionStartLineIndex = nil
        }
        guard selectionStartPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateSelection(to: point, isFinal: true)
    }

    func copySelectedTextToClipboard() -> Bool {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        return true
    }

    func selectAllText() -> Bool {
        let tokenRefs = lines.indices.flatMap { lineIndex in
            lines[lineIndex].tokens.indices.map { TokenRef(lineIndex: lineIndex, tokenIndex: $0) }
        }

        if tokenRefs.isEmpty {
            let lineIndices = Array(lines.indices)
            guard !lineIndices.isEmpty else { return false }
            selectedTokenRefs = []
            selectedLineIndices = Set(lineIndices)
            selectedText = lineIndices.map { lines[$0].text }.joined(separator: "\n")
            onSelectText?(selectedText, lineIndices, false)
        } else {
            selectedTokenRefs = Set(tokenRefs)
            selectedLineIndices = Set(tokenRefs.map(\.lineIndex))
            selectedText = selectedText(for: tokenRefs)
            onSelectText?(selectedText, Array(selectedLineIndices).sorted(), false)
        }
        needsDisplay = true
        return !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fittedImageRect() -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func displayRect(for normalizedRect: CGRect, in imageRect: NSRect) -> NSRect {
        NSRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    private func updateSelection(to point: NSPoint, isFinal: Bool) {
        guard let start = selectionStartPoint else { return }
        if hasTokenBoxes {
            let refs = selectionTokenRefs(from: start, to: point, startTokenRef: selectionStartTokenRef)
            selectedTokenRefs = Set(refs)
            selectedLineIndices = Set(refs.map(\.lineIndex))
            selectedText = selectedText(for: refs)
        } else {
            let indices = selectionIndices(from: start, to: point, startLineIndex: selectionStartLineIndex)
            selectedTokenRefs = []
            selectedLineIndices = Set(indices)
            selectedText = indices
                .compactMap { lines.indices.contains($0) ? lines[$0].text : nil }
                .joined(separator: "\n")
        }
        onSelectText?(selectedText, Array(selectedLineIndices).sorted(), isFinal)
    }

    private var hasTokenBoxes: Bool {
        lines.contains { !$0.tokens.isEmpty }
    }

    func clearSelection() {
        selectedTokenRefs.removeAll()
        selectedLineIndices.removeAll()
        selectedText = ""
        selectionStartPoint = nil
        selectionStartTokenRef = nil
        selectionStartLineIndex = nil
        needsDisplay = true
    }

    private func selectionIndices(
        from start: NSPoint,
        to current: NSPoint,
        startLineIndex: Int?
    ) -> [Int] {
        let imageRect = fittedImageRect()
        if let startLineIndex {
            let targetIndex = lineIndex(at: current, in: imageRect)
                ?? nearestLineIndex(to: current, in: imageRect)
            guard let targetIndex else { return [startLineIndex] }
            return contiguousIndices(from: startLineIndex, to: targetIndex)
        }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).insetBy(dx: -5, dy: -5)
        let hits = lines.indices.filter { index in
            lineHitRect(at: index, in: imageRect).intersects(rect)
        }
        return contiguousIndices(covering: hits)
    }

    private func selectionTokenRefs(
        from start: NSPoint,
        to current: NSPoint,
        startTokenRef: TokenRef?
    ) -> [TokenRef] {
        let imageRect = fittedImageRect()
        if let startTokenRef {
            let target = tokenRef(at: current, in: imageRect)
                ?? nearestTokenRef(to: current, in: imageRect)
            guard let target else { return [startTokenRef] }
            return contiguousTokenRefs(from: startTokenRef, to: target)
        }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).insetBy(dx: -4, dy: -4)

        return orderedTokenRefs().filter { ref in
            tokenHitRect(ref, in: imageRect).intersects(rect)
        }
    }

    private func lineIndex(at point: NSPoint, in imageRect: NSRect) -> Int? {
        for index in lines.indices.reversed() {
            if lineHitRect(at: index, in: imageRect).contains(point) {
                return index
            }
        }
        return nil
    }

    private func nearestLineIndex(to point: NSPoint, in imageRect: NSRect) -> Int? {
        lines.indices.min { lhs, rhs in
            let leftDistance = distance(from: point, to: lineHitRect(at: lhs, in: imageRect))
            let rightDistance = distance(from: point, to: lineHitRect(at: rhs, in: imageRect))
            return leftDistance < rightDistance
        }
    }

    private func lineHitRect(at index: Int, in imageRect: NSRect) -> NSRect {
        displayRect(for: lines[index].boundingBox, in: imageRect).insetBy(dx: -4, dy: -3)
    }

    private func tokenRef(at point: NSPoint, in imageRect: NSRect) -> TokenRef? {
        for ref in orderedTokenRefs().reversed() where tokenHitRect(ref, in: imageRect).contains(point) {
            return ref
        }
        return nil
    }

    private func nearestTokenRef(to point: NSPoint, in imageRect: NSRect) -> TokenRef? {
        orderedTokenRefs().min { lhs, rhs in
            let leftDistance = distance(from: point, to: tokenHitRect(lhs, in: imageRect))
            let rightDistance = distance(from: point, to: tokenHitRect(rhs, in: imageRect))
            return leftDistance < rightDistance
        }
    }

    private func tokenHitRect(_ ref: TokenRef, in imageRect: NSRect) -> NSRect {
        tokenDisplayRect(ref, in: imageRect).insetBy(dx: -2, dy: -2)
    }

    private func tokenDisplayRect(_ ref: TokenRef, in imageRect: NSRect) -> NSRect {
        guard lines.indices.contains(ref.lineIndex),
              lines[ref.lineIndex].tokens.indices.contains(ref.tokenIndex) else {
            return .zero
        }
        return displayRect(for: lines[ref.lineIndex].tokens[ref.tokenIndex].boundingBox, in: imageRect)
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }

    private func contiguousIndices(from start: Int, to end: Int) -> [Int] {
        guard lines.indices.contains(start), lines.indices.contains(end) else { return [] }
        return Array(min(start, end)...max(start, end))
    }

    private func contiguousIndices(covering indices: [Int]) -> [Int] {
        guard let first = indices.min(), let last = indices.max() else { return [] }
        return contiguousIndices(from: first, to: last)
    }

    private func orderedTokenRefs() -> [TokenRef] {
        lines.indices.flatMap { lineIndex in
            lines[lineIndex].tokens.indices.map { TokenRef(lineIndex: lineIndex, tokenIndex: $0) }
        }
    }

    private func orderedSelectedTokenRefs() -> [TokenRef] {
        orderedTokenRefs().filter { selectedTokenRefs.contains($0) }
    }

    private func contiguousTokenRefs(from start: TokenRef, to end: TokenRef) -> [TokenRef] {
        let ordered = orderedTokenRefs()
        guard let startIndex = ordered.firstIndex(of: start),
              let endIndex = ordered.firstIndex(of: end) else {
            return []
        }
        return Array(ordered[min(startIndex, endIndex)...max(startIndex, endIndex)])
    }

    private func selectedText(for refs: [TokenRef]) -> String {
        let grouped = Dictionary(grouping: refs, by: \.lineIndex)
        return grouped.keys.sorted().compactMap { lineIndex in
            guard lines.indices.contains(lineIndex),
                  let refs = grouped[lineIndex] else {
                return nil
            }
            let tokens = refs.sorted { $0.tokenIndex < $1.tokenIndex }.compactMap { ref -> String? in
                guard lines[lineIndex].tokens.indices.contains(ref.tokenIndex) else { return nil }
                return lines[lineIndex].tokens[ref.tokenIndex].text
            }
            return joinTokenTexts(tokens)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func joinTokenTexts(_ tokens: [String]) -> String {
        tokens.reduce(into: "") { result, token in
            guard !token.isEmpty else { return }
            if let previous = result.last,
               let first = token.first,
               shouldInsertSpace(between: previous, and: first) {
                result.append(" ")
            }
            result.append(token)
        }
    }

    private func shouldInsertSpace(between previous: Character, and next: Character) -> Bool {
        if previous.isCJKLike || next.isCJKLike { return false }
        if "([{<“‘\"".contains(previous) { return false }
        if ".,;:!?)]}>，。！？、；：”’\"".contains(next) { return false }
        return true
    }

    private func textBlockRects(
        for lineIndex: Int,
        line: RecognizedTextLine,
        in imageRect: NSRect
    ) -> [NSRect] {
        guard !line.tokens.isEmpty else {
            return [lineHitRect(at: lineIndex, in: imageRect).insetBy(dx: -3, dy: -2)]
        }

        let rects = line.tokens.indices.map {
            tokenDisplayRect(TokenRef(lineIndex: lineIndex, tokenIndex: $0), in: imageRect)
                .insetBy(dx: -3, dy: -2)
        }
        return mergedInlineRects(rects)
    }

    private func selectedTextRects(in imageRect: NSRect) -> [NSRect] {
        if selectedTokenRefs.isEmpty {
            return selectedLineIndices.sorted().compactMap { lineIndex in
                guard lines.indices.contains(lineIndex) else { return nil }
                return lineHitRect(at: lineIndex, in: imageRect).insetBy(dx: -3, dy: -2)
            }
        }

        let grouped = Dictionary(grouping: orderedSelectedTokenRefs(), by: \.lineIndex)
        return grouped.keys.sorted().flatMap { lineIndex in
            guard let refs = grouped[lineIndex] else { return [NSRect]() }
            let rects = refs.sorted { $0.tokenIndex < $1.tokenIndex }.map {
                tokenDisplayRect($0, in: imageRect).insetBy(dx: -2, dy: -1)
            }
            return mergedInlineRects(rects, maxGap: 4)
        }
    }

    private func mergedInlineRects(_ rects: [NSRect], maxGap: CGFloat? = nil) -> [NSRect] {
        guard !rects.isEmpty else { return [] }
        let sorted = rects.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > max(lhs.height, rhs.height) * 0.45 {
                return lhs.midY > rhs.midY
            }
            return lhs.minX < rhs.minX
        }

        var merged: [NSRect] = []
        for rect in sorted {
            guard rect.width > 1, rect.height > 1 else { continue }
            if let last = merged.last {
                let gap = rect.minX - last.maxX
                let verticalOverlap = min(last.maxY, rect.maxY) - max(last.minY, rect.minY)
                let threshold = maxGap ?? max(8, min(last.height, rect.height) * 0.9)
                if gap <= threshold, verticalOverlap > min(last.height, rect.height) * 0.35 {
                    merged[merged.count - 1] = last.union(rect)
                    continue
                }
            }
            merged.append(rect)
        }
        return merged
    }

    private func drawDimMask(excluding rects: [NSRect]) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        for rect in rects where rect.width > 1 && rect.height > 1 {
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCopyableTextBackplates(_ rects: [NSRect]) {
        let path = NSBezierPath()
        for rect in rects where rect.width > 1 && rect.height > 1 {
            path.append(NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5))
        }
        NSColor.white.withAlphaComponent(0.24).setFill()
        path.fill()
    }

    private func drawSelectedTextRect(_ rect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
        path.fill()
    }
}

private extension Character {
    var isCJKLike: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}
