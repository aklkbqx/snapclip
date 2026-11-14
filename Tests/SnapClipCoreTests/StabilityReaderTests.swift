import Foundation
import Testing
@testable import SnapClipCore

@Suite("StabilityReader")
struct StabilityReaderTests {
    @Test("Reads valid PNG immediately and extracts dimensions and SHA-256")
    func readsValidPNG() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = TestFixtures.makeValidPNGData(width: 64, height: 32)
        let file = dir.appendingPathComponent("valid.png")
        try png.write(to: file)

        let reader = StabilityReader(retryDelaysMilliseconds: [10], stabilityProbeMilliseconds: 10)
        let artifact = await reader.readCompleteImage(at: file)

        #expect(artifact != nil)
        #expect(artifact?.pixelWidth == 64)
        #expect(artifact?.pixelHeight == 32)
        #expect(artifact?.data == png)
        #expect(artifact?.contentType == .png)
    }

    @Test("Retries truncated PNG and succeeds once trailer is written")
    func retriesTruncatedPNG() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = TestFixtures.makeValidPNGData(width: 40, height: 20)
        let file = dir.appendingPathComponent("flushing.png")
        let partialCount = png.count - 12
        try png.prefix(partialCount).write(to: file)

        Task {
            try? await Task.sleep(nanoseconds: 35_000_000)
            try? png.write(to: file, options: .atomic)
        }

        let reader = StabilityReader(retryDelaysMilliseconds: [15, 25, 40, 80, 120], stabilityProbeMilliseconds: 10)
        let artifact = await reader.readCompleteImage(at: file)

        #expect(artifact != nil)
        #expect(artifact?.pixelWidth == 40)
        #expect(artifact?.pixelHeight == 20)
    }

    @Test("Rejects permanently corrupt PNG after retry schedule expires")
    func rejectsCorruptPNG() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let garbage = Data(repeating: 0xAA, count: 128)
        let file = dir.appendingPathComponent("corrupt.png")
        try garbage.write(to: file)

        let reader = StabilityReader(retryDelaysMilliseconds: [5, 10], stabilityProbeMilliseconds: 5)
        let artifact = await reader.readCompleteImage(at: file)
        #expect(artifact == nil)
    }

    @Test("Reads JPEG after verifying byte count remains stable")
    func readsJPEG() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let jpeg = TestFixtures.makeValidJPEGData(width: 30, height: 18)
        let file = dir.appendingPathComponent("shot.jpg")
        try jpeg.write(to: file)

        let reader = StabilityReader(retryDelaysMilliseconds: [10, 20], stabilityProbeMilliseconds: 15)
        let artifact = await reader.readCompleteImage(at: file)

        #expect(artifact != nil)
        #expect(artifact?.contentType == .jpeg)
        #expect(artifact?.pixelWidth == 30)
        #expect(artifact?.pixelHeight == 18)
    }

    @Test("Video stability waits for size to stop changing")
    func videoStabilityWaitsForSteadySize() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mov = dir.appendingPathComponent("recording.mov")
        try Data(repeating: 0x01, count: 64).write(to: mov)

        Task {
            try? await Task.sleep(nanoseconds: 40_000_000)
            try? Data(repeating: 0x02, count: 256).write(to: mov)
        }

        let reader = StabilityReader(retryDelaysMilliseconds: [10], stabilityProbeMilliseconds: 10)
        let stable = await reader.waitUntilVideoStable(at: mov, maxAttempts: 10)
        #expect(stable == true)
    }
}
