import AppKit
import Foundation
import SnapClipCore

/// Interactive floating preview view supporting click-to-open, drag-to-drop, swipe/right-click dismiss, and hover quick actions.
@MainActor
final class ThumbnailPreviewView: NSView, NSDraggingSource {
    private let image: NSImage
    private let fileURL: URL?
    private let mediaKind: PreviewMediaKind
    private let onClick: () -> Void
    private let onDismiss: () -> Void
    private let onTrash: (() -> Void)?
    private let onHoverChange: (Bool) -> Void

    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var closeButton: NSButton?
    private var trashButton: NSButton?

    init(
        frame: NSRect,
        image: NSImage,
        fileURL: URL?,
        mediaKind: PreviewMediaKind = .image,
        onClick: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onTrash: (() -> Void)?,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        self.image = image
        self.fileURL = fileURL
        self.mediaKind = mediaKind
        self.onClick = onClick
        self.onDismiss = onDismiss
        self.onTrash = onTrash
        self.onHoverChange = onHoverChange
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor

        switch (mediaKind, fileURL) {
        case (.video, .some):
            toolTip = "Click to open recording, drag to another app, right-click to dismiss"
        case (.image, .some):
            toolTip = "Click to open in Preview, drag to another app, right-click to dismiss"
        default:
            toolTip = "Drag to another app, right-click to dismiss"
        }

        setupActionButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupActionButtons() {
        let buttonSize: CGFloat = 22
        let padding: CGFloat = 8
        let closeBtn = makeActionButton(
            symbolName: "xmark",
            accessibilityLabel: "Dismiss preview",
            action: #selector(handleClosePressed)
        )
        closeBtn.frame = NSRect(
            x: bounds.width - buttonSize - padding,
            y: bounds.height - buttonSize - padding,
            width: buttonSize,
            height: buttonSize
        )
        closeBtn.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeBtn)
        closeButton = closeBtn

        if fileURL != nil, onTrash != nil {
            let trashLabel: String
            switch mediaKind {
            case .video: trashLabel = "Move recording to Trash"
            case .image: trashLabel = "Move screenshot to Trash"
            }
            let trashBtn = makeActionButton(
                symbolName: "trash",
                accessibilityLabel: trashLabel,
                action: #selector(handleTrashPressed)
            )
            trashBtn.frame = NSRect(
                x: closeBtn.frame.minX - buttonSize - 6,
                y: closeBtn.frame.minY,
                width: buttonSize,
                height: buttonSize
            )
            trashBtn.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(trashBtn)
            trashButton = trashBtn
        }
    }

    private func makeActionButton(
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 11
        btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.82).cgColor
        btn.contentTintColor = .white
        if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            btn.image = sym.withSymbolConfiguration(config)
        } else {
            btn.title = symbolName == "xmark" ? "×" : "⌫"
        }
        btn.toolTip = accessibilityLabel
        btn.target = self
        btn.action = action
        btn.alphaValue = 0.0
        btn.isHidden = true
        return btn
    }

    @objc private func handleClosePressed() {
        onDismiss()
    }

    @objc private func handleTrashPressed() {
        onTrash?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHoverChange(true)
        layer?.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
        setActionButtonsVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverChange(false)
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        setActionButtonsVisible(false)
    }

    private func setActionButtonsVisible(_ visible: Bool) {
        let buttons = [closeButton, trashButton].compactMap { $0 }
        for btn in buttons {
            if visible { btn.isHidden = false }
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            for btn in buttons {
                btn.animator().alphaValue = visible ? 1.0 : 0.0
            }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isHovered else { return }
                self.closeButton?.isHidden = true
                self.trashButton?.isHidden = true
            }
        })
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let insetBounds = bounds.insetBy(dx: 4, dy: 4)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        let clipPath = NSBezierPath(roundedRect: insetBounds, xRadius: 8, yRadius: 8)
        clipPath.addClip()

        let imgSize = image.size
        if imgSize.width > 0 && imgSize.height > 0 {
            let viewRatio = insetBounds.width / max(insetBounds.height, 1)
            let imgRatio = imgSize.width / max(imgSize.height, 1)
            let ratioDelta = max(viewRatio / imgRatio, imgRatio / viewRatio)
            // Use aspect-fit for extreme wide/tall captures so edges stay visible; aspect-fill otherwise.
            let scale = ratioDelta > 1.65
                ? min(insetBounds.width / imgSize.width, insetBounds.height / imgSize.height)
                : max(insetBounds.width / imgSize.width, insetBounds.height / imgSize.height)

            let drawW = imgSize.width * scale
            let drawH = imgSize.height * scale
            let rawRect = NSRect(
                x: insetBounds.midX - drawW / 2,
                y: insetBounds.midY - drawH / 2,
                width: drawW,
                height: drawH
            )
            let drawRect = backingAlignedRect(rawRect, options: .alignAllEdgesNearest)
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()

        if case .video = mediaKind {
            drawVideoPlayOverlay(in: insetBounds)
        }
        drawStatusBadge()
    }

    private func drawVideoPlayOverlay(in rect: NSRect) {
        let circleSize: CGFloat = 28
        let rawCircleRect = NSRect(
            x: rect.midX - circleSize / 2,
            y: rect.midY - circleSize / 2,
            width: circleSize,
            height: circleSize
        )
        let circleRect = backingAlignedRect(rawCircleRect, options: .alignAllEdgesNearest)
        let circlePath = NSBezierPath(ovalIn: circleRect)
        NSColor(calibratedWhite: 0.05, alpha: 0.72).setFill()
        circlePath.fill()
        NSColor.white.withAlphaComponent(0.65).setStroke()
        circlePath.lineWidth = 1.0
        circlePath.stroke()

        if let sym = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            let styled = sym.withSymbolConfiguration(config) ?? sym
            let symSize = styled.size
            let rawIconRect = NSRect(
                x: circleRect.midX - symSize.width / 2 + 1,
                y: circleRect.midY - symSize.height / 2,
                width: symSize.width,
                height: symSize.height
            )
            let iconRect = backingAlignedRect(rawIconRect, options: .alignAllEdgesNearest)
            styled.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.95)
        }
    }

    private func drawStatusBadge() {
        let badgeString: String
        switch mediaKind {
        case .image:
            badgeString = "Copied"
        case .video(let duration):
            if let duration, duration > 0 {
                let totalSeconds = max(1, Int(duration.rounded()))
                badgeString = String(format: "Saved · %d:%02d", totalSeconds / 60, totalSeconds % 60)
            } else {
                badgeString = "Saved"
            }
        }
        let badgeText = badgeString as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = badgeText.size(withAttributes: attrs)
        let rawBadgeRect = NSRect(
            x: 10,
            y: bounds.height - textSize.height - 14,
            width: textSize.width + 12,
            height: textSize.height + 4
        )
        let badgeRect = backingAlignedRect(rawBadgeRect, options: .alignAllEdgesNearest)
        NSColor(calibratedWhite: 0.05, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6).fill()
        badgeText.draw(
            at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !didStartDrag else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - start.x
        let dy = current.y - start.y
        if hypot(dx, dy) < 5 { return }

        if dx > 28 && abs(dy) < 24 {
            didStartDrag = true
            onDismiss()
            return
        }

        didStartDrag = true
        let writer: any NSPasteboardWriting = (fileURL as NSURL?) ?? image
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if !didStartDrag {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDismiss()
    }
}
