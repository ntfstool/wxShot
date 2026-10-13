import AppKit

/// Document view of the editor scroll view. It simply keeps its frame equal to
/// the (possibly rotated) canvas and pins the canvas to the origin.
final class CanvasContainerView: NSView {
    private(set) weak var canvasView: EditCanvasView?

    var innerImageSize: CGSize { canvasView?.orientedDisplaySize ?? .zero }

    init(canvasView: EditCanvasView) {
        self.canvasView = canvasView
        super.init(frame: NSRect(origin: .zero, size: canvasView.frame.size))
        addSubview(canvasView)
        canvasView.setFrameOrigin(.zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    /// Called when the canvas's intrinsic size changes (selection resize, rotation, long-screenshot preview).
    func canvasSizeDidChange() {
        guard let canvasView else { return }
        canvasView.setPresentationScale(canvasView.presentationScale)
        setFrameSize(canvasView.orientedDisplaySize)
        // frameRotation rotates around the frame origin, so re-anchor the rotated bounds at (0, 0).
        let rotatedBounds = canvasView.convert(canvasView.bounds, to: self)
        canvasView.setFrameOrigin(NSPoint(
            x: canvasView.frame.origin.x - rotatedBounds.minX,
            y: canvasView.frame.origin.y - rotatedBounds.minY
        ))
        needsDisplay = true
    }
}
