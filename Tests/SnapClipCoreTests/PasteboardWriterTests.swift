import AppKit
import Foundation
import Testing
@testable import SnapClipCore

@Suite("PasteboardEncoderAndCache")
struct PasteboardWriterTests {
    @Test("Encodes PNG input directly and attaches readable TIFF representation")
    func encodesPNGAndTIFF() throws {
        let png = TestFixtures.makeValidPNGData(width: 36, height: 24)
        let payload = PasteboardImageEncoder.encode(data: png, contentType: .png, includeTiff: true)

        #expect(payload != nil)
        #expect(payload?.pngData == png)
        #expect(payload?.tiffData != nil)
        if let tiff = payload?.tiffData {
            let rep = NSBitmapImageRep(data: tiff)
            #expect(rep?.pixelsWide == 36)
            #expect(rep?.pixelsHigh == 24)
        }
    }

    @Test("Omits TIFF when disabled")
    func omitsTIFFWhenDisabled() {
        let png = TestFixtures.makeValidPNGData(width: 16, height: 16)
        let payload = PasteboardImageEncoder.encode(data: png, contentType: .png, includeTiff: false)

        #expect(payload != nil)
        #expect(payload?.tiffData == nil)
    }

    @Test("Transcodes JPEG input into valid PNG plus TIFF")
    func transcodesJPEGToPNG() {
        let jpeg = TestFixtures.makeValidJPEGData(width: 28, height: 14)
        let payload = PasteboardImageEncoder.encode(data: jpeg, contentType: .jpeg, includeTiff: true)

        #expect(payload != nil)
        if let png = payload?.pngData {
            let dims = StabilityReader.decodePixelDimensions(from: png)
            #expect(dims?.width == 28)
            #expect(dims?.height == 14)
        }
        #expect(payload?.tiffData != nil)
    }

    @Test("Returns nil for invalid image data")
    func returnsNilOnInvalidBytes() {
        let invalid = Data("not-an-image".utf8)
        let payload = PasteboardImageEncoder.encode(data: invalid, contentType: .jpeg, includeTiff: true)
        #expect(payload == nil)
    }

    @Test("BoundedKeyValueCache evicts oldest key after hitting capacity")
    func boundedCacheEviction() {
        var cache = BoundedKeyValueCache<String, String>(capacity: 2)
        cache["a"] = "1"
        cache["b"] = "2"
        cache["c"] = "3"

        #expect(cache["a"] == nil)
        #expect(cache["b"] == "2")
        #expect(cache["c"] == "3")
    }

    @Test("Writes file URL to an isolated pasteboard for video clipboard paste")
    func writesFileURLToIsolatedPasteboard() async throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mov = dir.appendingPathComponent("Screen Recording.mov")
        try await TestFixtures.makeValidMOVFile(at: mov, durationSeconds: 0.2)

        let (wrote, readPaths) = await MainActor.run {
            let pb = NSPasteboard.withUniqueName()
            defer { pb.releaseGlobally() }
            let ok = SystemPasteboardWriter.writeFileURL(mov, to: pb)
            let objs = pb.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            return (ok, objs.map { $0.standardizedFileURL.path })
        }

        #expect(wrote == true)
        #expect(readPaths == [mov.standardizedFileURL.path])

        let missing = dir.appendingPathComponent("missing.mov")
        let missingResult = await SystemPasteboardWriter().writeFileURL(missing)
        #expect(missingResult == false)
    }
}
