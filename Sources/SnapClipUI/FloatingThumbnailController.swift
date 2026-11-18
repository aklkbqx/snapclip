import AppKit
import Foundation
import SnapClipCore

/// Presents a non-activating floating screenshot preview on the display where the mouse cursor resides.
@MainActor
public final class FloatingThumbnailController: PreviewPresenting {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var currentFileURL: URL?
    private var isDismissing = false

    public init() {}

    nonisolated public func showPreview(
        imageData: Data,
        fileURL: URL?,
        autoDismissSeconds: Double,
        hoverDismissSeconds: Double,
        onTrashRequested: @escaping @Sendable (URL) -> Bool
    ) async {
        await showMediaPreview(
            imageData: imageData,
            fileURL: fileURL,
            mediaKind: .image,
            autoDismissSeconds: autoDismissSeconds,
            hoverDismissSeconds: hoverDismissSeconds,
            onTrashRequested: onTrashRequested
        )
    }

    nonisolated public func showMediaPreview(
        imageData: Data?,
        fileURL: URL?,
        mediaKind: PreviewMediaKind,
        autoDismissSeconds: Double,
        hoverDismissSeconds: Double,
        onTrashRequested: @escaping @Sendable (URL) -> Bool
    ) async {
        await MainActor.run {
            let resolvedImage: NSImage?
            if let imageData, let decoded = NSImage(data: imageData) {
                resolvedImage = decoded
            } else if case .video = mediaKind {
                resolvedImage = Self.makeVideoFallbackImage()
            } else {
                resolvedImage = nil
            }
            guard let image = resolvedImage else { return }
            self.show(
                image: image,
                fileURL: fileURL,
                mediaKind: mediaKind,
                autoDismissSeconds: autoDismissSeconds,
                hoverDismissSeconds: hoverDismissSeconds,
                onTrashRequested: onTrashRequested
            )
        }
    }

    public func show(
        image: NSImage,
        fileURL: URL?,
        mediaKind: PreviewMediaKind = .image,
        autoDismissSeconds: Double = 4.5,
        hoverDismissSeconds: Double = 2.5,
        onTrashRequested: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) {
        dismissImmediately()
        currentFileURL = fileURL
        isDismissing = false

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let maxW: CGFloat = 204
        let maxH: CGFloat = 148
        let minW: CGFloat = 112
        let minH: CGFloat = 76

        let imgW = max(image.size.width, 1)
        let imgH = max(image.size.height, 1)
        let scale = min(maxW / imgW, maxH / imgH)
        let width = min(max(imgW * scale, minW), maxW)
        let height = min(max(imgH * scale, minH), maxH)

        let targetFrame = NSRect(
            x: visibleFrame.maxX - width - 20,
            y: visibleFrame.minY + 20,
            width: width,
            height: height
        )
        let startFrame = targetFrame.offsetBy(dx: width + 30, dy: 0)

        let panel = NSPanel(
            contentRect: startFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let trashHandler: (() -> Void)? = fileURL.map { url in
            { [weak self] in
                if onTrashRequested(url) {
                    self?.animateOut()
                }
            }
        }

        let view = ThumbnailPreviewView(
            frame: NSRect(origin: .zero, size: targetFrame.size),
            image: image,
            fileURL: fileURL,
            mediaKind: mediaKind,
            onClick: { [weak self] in
                self?.openInPreview()
            },
            onDismiss: { [weak self] in
                self?.animateOut()
            },
            onTrash: trashHandler,
            onHoverChange: { [weak self] hovering in
                guard let self, !self.isDismissing else { return }
                if hovering {
                    self.dismissTimer?.invalidate()
                } else {
                    self.scheduleDismiss(after: hoverDismissSeconds)
                }
            }
        )

        panel.contentView = view
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1.0
        }

        scheduleDismiss(after: autoDismissSeconds)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.animateOut()
            }
        }
    }

    private func openInPreview() {
        guard !isDismissing else { return }
        if let url = currentFileURL {
            NSWorkspace.shared.open(url)
        }
        animateOut()
    }

    private func animateOut() {
        guard !isDismissing, let panel = self.panel else { return }
        isDismissing = true
        dismissTimer?.invalidate()
        dismissTimer = nil

        let exitFrame = panel.frame.offsetBy(dx: panel.frame.width + 30, dy: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(exitFrame, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                if self?.panel === panel {
                    self?.panel = nil
                    self?.isDismissing = false
                }
            }
        })
    }

    private func dismissImmediately() {
        isDismissing = false
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func makeVideoFallbackImage() -> NSImage {
        let size = NSSize(width: 204, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedWhite: 0.14, alpha: 1.0).setFill()
            rect.fill()
            if let sym = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Screen Recording") {
                let config = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
                    .applying(.init(paletteColors: [.white]))
                let styled = sym.withSymbolConfiguration(config) ?? sym
                let symSize = styled.size
                let drawRect = NSRect(
                    x: (rect.width - symSize.width) / 2,
                    y: (rect.height - symSize.height) / 2,
                    width: symSize.width,
                    height: symSize.height
                )
                styled.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.45)
            }
            return true
        }
    }
}
