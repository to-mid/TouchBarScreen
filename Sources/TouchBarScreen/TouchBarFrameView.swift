import AppKit

final class TouchBarFrameView: NSView {
    private var image: NSImage?
    private var cursorPosition = CGPoint(x: 0.5, y: 0.5)

    var detailMagnification: CGFloat = 1 {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 600, height: 30)
    }

    override var isFlipped: Bool {
        true
    }

    func setFrameImage(_ cgImage: CGImage, cursorPosition: CGPoint) {
        image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        self.cursorPosition = cursorPosition
        needsDisplay = true
    }

    func clearFrame() {
        image = nil
        cursorPosition = CGPoint(x: 0.5, y: 0.5)
        needsDisplay = true
    }

    func updateCursorPosition(_ position: CGPoint) {
        cursorPosition = position
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard let image else {
            drawPlaceholder()
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .high

        let contentBounds = bounds.insetBy(dx: 1, dy: 1)
        let previewWidth = min(
            88,
            max(
                42,
                contentBounds.height * image.size.width / image.size.height
            )
        )
        let previewRect = CGRect(
            x: contentBounds.minX,
            y: contentBounds.minY,
            width: previewWidth,
            height: contentBounds.height
        )
        drawFullPreview(image, in: previewRect)

        let dividerX = previewRect.maxX + 4
        let detailRect = CGRect(
            x: dividerX + 4,
            y: contentBounds.minY,
            width: max(0, contentBounds.maxX - dividerX - 4),
            height: contentBounds.height
        )

        NSColor.separatorColor.setFill()
        CGRect(
            x: dividerX,
            y: contentBounds.minY + 3,
            width: 1,
            height: max(0, contentBounds.height - 6)
        ).fill()

        drawCursorDetail(image, in: detailRect)
    }

    private func drawFullPreview(_ image: NSImage, in rect: CGRect) {
        let destination = ImageLayout.destinationRect(
            imageSize: image.size,
            bounds: rect,
            mode: .aspectFit
        )
        image.draw(
            in: destination,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        NSColor.white.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(rect: destination.integral)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawCursorDetail(_ image: NSImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let sourceWidth = min(
            image.size.width,
            rect.width / detailMagnification
        )
        let sourceHeight = min(
            image.size.height,
            rect.height / detailMagnification
        )
        let cursorX = cursorPosition.x * image.size.width
        let cursorY = (1 - cursorPosition.y) * image.size.height
        let originX = min(
            max(0, cursorX - sourceWidth / 2),
            image.size.width - sourceWidth
        )
        let originY = min(
            max(0, cursorY - sourceHeight / 2),
            image.size.height - sourceHeight
        )
        let sourceRect = CGRect(
            x: originX,
            y: originY,
            width: sourceWidth,
            height: sourceHeight
        )

        image.draw(
            in: rect,
            from: sourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private func drawPlaceholder() {
        let text = "等待虚拟屏幕画面..."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
}
