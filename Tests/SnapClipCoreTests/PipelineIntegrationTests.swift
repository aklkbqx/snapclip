import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SnapClipCore

final class MockPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var writes: [(data: Data, contentType: UTType, includeTiff: Bool)] = []

    func writeImage(data: Data, contentType: UTType, includeTiff: Bool) async -> Bool {
        lock.withLock {
            writes.append((data, contentType, includeTiff))
        }
        return true
    }
}

final class MockPreviewPresenter: PreviewPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shownURLs: [URL?] = []

    func showPreview(
        imageData: Data,
        fileURL: URL?,
        autoDismissSeconds: Double,
        hoverDismissSeconds: Double,
        onTrashRequested: @escaping @Sendable (URL) -> Bool
    ) async {
        lock.withLock {
            shownURLs.append(fileURL)
        }
    }
}

final class RecordingSink: CaptureActionSink, @unchecked Sendable {
    let id = "recording-sink"
    private let lock = NSLock()
    private(set) var received: [(fileName: String, destinationPath: String?)] = []

    func handle(_ artifact: CapturedArtifact, destinationURL: URL?) async {
        lock.withLock {
            received.append((artifact.fileName, destinationURL?.path))
        }
    }
}

final class TestLogger: SnapClipLogging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var messages: [String] = []

    func log(_ message: String) {
        lock.withLock {
            messages.append(message)
        }
    }
}

@Suite("PipelineAndWatcher")
struct PipelineIntegrationTests {
    @Test("Copies to pasteboard, moves file to destination, presents preview, and invokes sinks")
    func fullPipelineKeepFile() async throws {
        let staging = try TestFixtures.makeTempDirectory()
        let dest = try TestFixtures.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: dest)
        }

        let png = TestFixtures.makeValidPNGData(width: 48, height: 32)
        let source = staging.appendingPathComponent("Screenshot 1.png")
        try png.write(to: source)

        let artifact = CapturedArtifact(
            sourceURL: source,
            data: png,
            contentType: .png,
            pixelWidth: 48,
            pixelHeight: 32
        )

        let pasteboard = MockPasteboardWriter()
        let preview = MockPreviewPresenter()
        let sink = RecordingSink()
        let pipeline = SnapClipPipeline(
            config: SnapClipConfig(keepFile: true, showFloatingPreview: true),
            pasteboardWriter: pasteboard,
            previewPresenter: preview,
            sinks: [sink],
            logger: TestLogger()
        )

        let outcome = await pipeline.runImagePipeline(
            artifact,
            alreadyCopiedDigest: nil,
            destinationDirectory: dest
        )

        let expectedDest = dest.appendingPathComponent("Screenshot 1.png").path
        #expect(pasteboard.writes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: expectedDest))
        #expect(preview.shownURLs.first??.path == expectedDest)
        #expect(sink.received.count == 1)
        #expect(sink.received.first?.destinationPath == expectedDest)
        #expect(outcome.result == CaptureProcessingResult.processedImage(
            fileName: "Screenshot 1.png",
            copiedToClipboard: true,
            destinationPath: expectedDest
        ))
    }

    @Test("Clipboard-only mode deletes staging file after copying")
    func clipboardOnlyRemovesStagingFile() async throws {
        let staging = try TestFixtures.makeTempDirectory()
        let dest = try TestFixtures.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: dest)
        }

        let png = TestFixtures.makeValidPNGData()
        let source = staging.appendingPathComponent("ClipOnly.png")
        try png.write(to: source)

        let artifact = CapturedArtifact(
            sourceURL: source,
            data: png,
            contentType: .png,
            pixelWidth: 24,
            pixelHeight: 16
        )

        let pasteboard = MockPasteboardWriter()
        let pipeline = SnapClipPipeline(
            config: SnapClipConfig(keepFile: false, showFloatingPreview: false),
            pasteboardWriter: pasteboard,
            logger: TestLogger()
        )

        let outcome = await pipeline.runImagePipeline(
            artifact,
            alreadyCopiedDigest: nil,
            destinationDirectory: dest
        )

        #expect(pasteboard.writes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: dest.appendingPathComponent("ClipOnly.png").path))
        #expect(outcome.result == CaptureProcessingResult.processedImage(
            fileName: "ClipOnly.png",
            copiedToClipboard: true,
            destinationPath: nil
        ))
    }

    @Test("CaptureWatcher picks up pre-existing and newly written screenshots on startup")
    func watcherProcessesStartupAndLiveFiles() async throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let config = SnapClipConfig(
            stagingDirectory: "~/staging",
            destinationDirectory: "~/dest",
            stateDirectory: "~/state",
            logPath: "~/logs/snapclip.log",
            keepFile: true,
            showFloatingPreview: false
        )
        let stagingURL = config.stagingURL(homeDirectory: home.path)
        let destURL = config.destinationURL(homeDirectory: home.path)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        // Pre-existing capture landed before daemon startup
        let prePNG = TestFixtures.makeValidPNGData(width: 16, height: 16, color: .systemRed)
        try prePNG.write(to: stagingURL.appendingPathComponent("PreExisting.png"))

        let pasteboard = MockPasteboardWriter()
        let logger = TestLogger()
        let defaults = InMemoryDefaultsStore(initial: ["location-screenshot": stagingURL.path])
        let pipeline = SnapClipPipeline(config: config, pasteboardWriter: pasteboard, logger: logger)
        let watcher = CaptureWatcher(
            config: config,
            homeDirectory: home.path,
            pipeline: pipeline,
            stabilityReader: StabilityReader(retryDelaysMilliseconds: [15, 25], stabilityProbeMilliseconds: 15),
            defaultsStore: defaults,
            logger: logger
        )

        try watcher.start()
        defer { watcher.stop() }

        // Write a second screenshot after watcher has started
        try await Task.sleep(nanoseconds: 120_000_000)
        let livePNG = TestFixtures.makeValidPNGData(width: 20, height: 20, color: .systemGreen)
        try livePNG.write(to: stagingURL.appendingPathComponent("LiveShot.png"))

        for _ in 0..<40 {
            if pasteboard.writes.count == 2 &&
                FileManager.default.fileExists(atPath: destURL.appendingPathComponent("PreExisting.png").path) &&
                FileManager.default.fileExists(atPath: destURL.appendingPathComponent("LiveShot.png").path) {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(pasteboard.writes.count == 2)
        #expect(FileManager.default.fileExists(atPath: destURL.appendingPathComponent("PreExisting.png").path))
        #expect(FileManager.default.fileExists(atPath: destURL.appendingPathComponent("LiveShot.png").path))
        #expect(!FileManager.default.fileExists(atPath: stagingURL.appendingPathComponent("PreExisting.png").path))
        #expect(!FileManager.default.fileExists(atPath: stagingURL.appendingPathComponent("LiveShot.png").path))
    }

    @Test("CaptureWatcher processes multiple captures serially oldest-first without clipboard racing")
    func watcherPreservesChronologicalOrderUnderBatch() async throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let config = SnapClipConfig(
            stagingDirectory: "~/staging",
            destinationDirectory: "~/dest",
            stateDirectory: "~/state",
            logPath: "~/logs/snapclip.log",
            keepFile: true,
            showFloatingPreview: true
        )
        let stagingURL = config.stagingURL(homeDirectory: home.path)
        let destURL = config.destinationURL(homeDirectory: home.path)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        let firstPNG = TestFixtures.makeValidPNGData(width: 96, height: 96, color: .systemRed)
        let secondPNG = TestFixtures.makeValidPNGData(width: 16, height: 16, color: .systemGreen)
        try firstPNG.write(to: stagingURL.appendingPathComponent("1-OlderLarger.png"))
        try await Task.sleep(nanoseconds: 40_000_000)
        try secondPNG.write(to: stagingURL.appendingPathComponent("2-NewerSmaller.png"))

        let pasteboard = MockPasteboardWriter()
        let preview = MockPreviewPresenter()
        let pipeline = SnapClipPipeline(
            config: config,
            pasteboardWriter: pasteboard,
            previewPresenter: preview,
            logger: TestLogger()
        )
        let watcher = CaptureWatcher(
            config: config,
            homeDirectory: home.path,
            pipeline: pipeline,
            stabilityReader: StabilityReader(retryDelaysMilliseconds: [15, 25], stabilityProbeMilliseconds: 15),
            defaultsStore: InMemoryDefaultsStore(initial: ["location-screenshot": stagingURL.path]),
            logger: TestLogger()
        )

        try watcher.start()
        defer { watcher.stop() }

        for _ in 0..<40 {
            if preview.shownURLs.count == 2 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(pasteboard.writes.map(\.data) == [firstPNG, secondPNG])
        #expect(preview.shownURLs.compactMap { $0?.lastPathComponent } == ["1-OlderLarger.png", "2-NewerSmaller.png"])
        #expect(FileManager.default.fileExists(atPath: destURL.appendingPathComponent("1-OlderLarger.png").path))
        #expect(FileManager.default.fileExists(atPath: destURL.appendingPathComponent("2-NewerSmaller.png").path))
    }

    @Test("CaptureWatcher quarantines permanently unreadable staging files after bounded retries")
    func watcherQuarantinesCorruptFiles() async throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let config = SnapClipConfig(
            stagingDirectory: "~/staging",
            destinationDirectory: "~/dest",
            stateDirectory: "~/state",
            logPath: "~/logs/snapclip.log",
            keepFile: true,
            showFloatingPreview: false
        )
        let stagingURL = config.stagingURL(homeDirectory: home.path)
        let failedURL = config.stateURL(homeDirectory: home.path).appendingPathComponent("failed/broken.png")
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 100).write(to: stagingURL.appendingPathComponent("broken.png"))

        let pasteboard = MockPasteboardWriter()
        let watcher = CaptureWatcher(
            config: config,
            homeDirectory: home.path,
            pipeline: SnapClipPipeline(config: config, pasteboardWriter: pasteboard, logger: TestLogger()),
            stabilityReader: StabilityReader(retryDelaysMilliseconds: [10], stabilityProbeMilliseconds: 10),
            defaultsStore: InMemoryDefaultsStore(initial: ["location-screenshot": stagingURL.path]),
            logger: TestLogger(),
            maxFailureCycles: 2
        )

        try watcher.start()
        defer { watcher.stop() }

        for _ in 0..<60 {
            if FileManager.default.fileExists(atPath: failedURL.path) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(FileManager.default.fileExists(atPath: failedURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagingURL.appendingPathComponent("broken.png").path))
        #expect(pasteboard.writes.isEmpty)
    }
}
