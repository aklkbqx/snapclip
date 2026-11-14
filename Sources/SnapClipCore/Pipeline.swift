import Foundation

/// Transforms or annotates a captured artifact before sinks run (e.g. compression, OCR, redaction).
public protocol CapturePostProcessor: Sendable {
    var id: String { get }
    func process(_ artifact: CapturedArtifact) async throws -> CapturedArtifact
}

/// Receives a finalized artifact after post-processing (e.g. clipboard, preview UI, notifications).
public protocol CaptureActionSink: Sendable {
    var id: String { get }
    func handle(_ artifact: CapturedArtifact, destinationURL: URL?) async
}

/// UI presentation bridge invoked once an image has been copied and placed on disk.
public protocol PreviewPresenting: Sendable {
    func showPreview(
        imageData: Data,
        fileURL: URL?,
        autoDismissSeconds: Double,
        hoverDismissSeconds: Double,
        onTrashRequested: @escaping @Sendable (URL) -> Bool
    ) async
}

/// Coordinates post-processors, pasteboard copy, destination persistence, preview UI, and custom sinks.
public final class SnapClipPipeline: Sendable {
    private let config: SnapClipConfig
    private let pasteboardWriter: any PasteboardWriting
    private let destinationStore: DestinationStore
    private let previewPresenter: (any PreviewPresenting)?
    private let postProcessors: [any CapturePostProcessor]
    private let sinks: [any CaptureActionSink]
    private let logger: any SnapClipLogging

    public init(
        config: SnapClipConfig,
        pasteboardWriter: any PasteboardWriting,
        destinationStore: DestinationStore = DestinationStore(),
        previewPresenter: (any PreviewPresenting)? = nil,
        postProcessors: [any CapturePostProcessor] = [],
        sinks: [any CaptureActionSink] = [],
        logger: any SnapClipLogging = StandardLogger()
    ) {
        self.config = config
        self.pasteboardWriter = pasteboardWriter
        self.destinationStore = destinationStore
        self.previewPresenter = previewPresenter
        self.postProcessors = postProcessors
        self.sinks = sinks
        self.logger = logger
    }

    public func runImagePipeline(
        _ initialArtifact: CapturedArtifact,
        alreadyCopiedDigest: String?,
        destinationDirectory: URL
    ) async -> (result: CaptureProcessingResult, digest: String, previewShownPath: String?) {
        var artifact = initialArtifact
        for processor in postProcessors {
            do {
                artifact = try await processor.process(artifact)
            } catch {
                logger.log("post-processor '\(processor.id)' failed for \(artifact.fileName): \(error.localizedDescription)")
            }
        }

        var copied = false
        if alreadyCopiedDigest != artifact.sha256 {
            copied = await pasteboardWriter.writeImage(
                data: artifact.data,
                contentType: artifact.contentType,
                includeTiff: config.includeTiffOnPasteboard
            )
            if copied {
                logger.log("copied screenshot to clipboard: \(artifact.fileName) (\(artifact.data.count) bytes)")
            } else {
                logger.log("failed to write screenshot to clipboard: \(artifact.fileName)")
            }
        }

        let finalURL: URL?
        if config.keepFile {
            do {
                let moved = try destinationStore.moveToDestination(
                    from: artifact.sourceURL,
                    toDirectory: destinationDirectory
                )
                finalURL = moved
                logger.log("saved screenshot to \(moved.path)")
            } catch {
                logger.log("failed to move screenshot to \(destinationDirectory.path): \(error.localizedDescription)")
                finalURL = artifact.sourceURL
            }
        } else {
            try? FileManager.default.removeItem(at: artifact.sourceURL)
            finalURL = nil
            logger.log("clipboard-only mode: removed staging file \(artifact.fileName)")
        }

        var shownPath: String?
        if config.showFloatingPreview, let presenter = previewPresenter {
            let store = destinationStore
            let log = logger
            await presenter.showPreview(
                imageData: artifact.data,
                fileURL: finalURL,
                autoDismissSeconds: config.previewAutoDismissSeconds,
                hoverDismissSeconds: config.previewHoverDismissSeconds,
                onTrashRequested: { url in
                    do {
                        try store.trashFile(at: url)
                        log.log("trashed screenshot from floating preview: \(url.lastPathComponent)")
                        return true
                    } catch {
                        log.log("failed to trash screenshot \(url.lastPathComponent): \(error.localizedDescription)")
                        return false
                    }
                }
            )
            shownPath = finalURL?.path ?? artifact.sourceURL.path
        }

        for sink in sinks {
            await sink.handle(artifact, destinationURL: finalURL)
        }

        return (
            .processedImage(
                fileName: artifact.fileName,
                copiedToClipboard: copied || alreadyCopiedDigest == artifact.sha256,
                destinationPath: finalURL?.path
            ),
            artifact.sha256,
            shownPath
        )
    }
}
