import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Validates that newly discovered media files have finished flushing to disk without blocking the main thread.
public struct StabilityReader: Sendable {
    private static let pngTrailer = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    private static let jpegTrailer = Data([0xFF, 0xD9])

    public let retryDelaysNanoseconds: [UInt64]
    public let stabilityProbeNanoseconds: UInt64

    public init(
        retryDelaysMilliseconds: [UInt64] = [20, 30, 50, 75, 100, 150, 250, 400, 600, 800, 1_000, 1_000, 1_000, 1_000],
        stabilityProbeMilliseconds: UInt64 = 40
    ) {
        self.retryDelaysNanoseconds = retryDelaysMilliseconds.map { $0 * 1_000_000 }
        self.stabilityProbeNanoseconds = stabilityProbeMilliseconds * 1_000_000
    }

    /// Reads an image once its format trailer / byte size has stabilized and ImageIO confirms valid pixel dimensions.
    public func readCompleteImage(at url: URL) async -> CapturedArtifact? {
        let ext = url.pathExtension.lowercased()
        guard SupportedMedia.isImage(extension: ext) else { return nil }
        let contentType = SupportedMedia.contentType(forExtension: ext)

        for attempt in 0...retryDelaysNanoseconds.count {
            if let artifact = await tryReadImageOnce(at: url, ext: ext, contentType: contentType) {
                return artifact
            }
            if attempt < retryDelaysNanoseconds.count {
                try? await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
            }
        }
        return nil
    }

    /// Waits until a video file's size stops changing across two probes before allowing a move.
    public func waitUntilVideoStable(at url: URL, maxAttempts: Int = 40) async -> Bool {
        let probeGap = max(stabilityProbeNanoseconds, 200_000_000)
        var previousSize: Int64?
        for _ in 0..<maxAttempts {
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            let size = fileSize(at: url)
            if let prev = previousSize, size > 0, size == prev {
                return true
            }
            previousSize = size
            try? await Task.sleep(nanoseconds: probeGap)
        }
        return false
    }

    private func tryReadImageOnce(at url: URL, ext: String, contentType: UTType) async -> CapturedArtifact? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), data.count > 64 else { return nil }

        if ext == "png" {
            guard data.suffix(12) == Self.pngTrailer else { return nil }
            guard let dims = Self.decodePixelDimensions(from: data) else { return nil }
            return CapturedArtifact(
                sourceURL: url,
                data: data,
                contentType: contentType,
                pixelWidth: dims.width,
                pixelHeight: dims.height
            )
        }

        if ext == "jpg" || ext == "jpeg" {
            guard data.suffix(2) == Self.jpegTrailer else { return nil }
        }

        // Non-PNG images lack a guaranteed single-chunk EOF across all codecs (HEIC/TIFF/WebP),
        // so verify file byte count stays identical across a short probe before reading.
        let initialCount = data.count
        try? await Task.sleep(nanoseconds: stabilityProbeNanoseconds)
        guard let verifiedData = try? Data(contentsOf: url),
              verifiedData.count == initialCount,
              let dims = Self.decodePixelDimensions(from: verifiedData) else {
            return nil
        }

        return CapturedArtifact(
            sourceURL: url,
            data: verifiedData,
            contentType: contentType,
            pixelWidth: dims.width,
            pixelHeight: dims.height
        )
    }

    public static func decodePixelDimensions(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let num = attrs[.size] as? NSNumber else {
            return -1
        }
        return num.int64Value
    }
}
