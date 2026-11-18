import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Readiness classification for a staged screen recording file.
public enum VideoReadiness: Equatable, Sendable {
    case ready
    case inProgress
    case incomplete
}

/// Validates that newly discovered media files have finished flushing to disk without blocking the main thread.
public struct StabilityReader: Sendable {
    private static let pngTrailer = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    private static let jpegTrailer = Data([0xFF, 0xD9])

    public let retryDelaysNanoseconds: [UInt64]
    public let stabilityProbeNanoseconds: UInt64
    public let videoProbeNanoseconds: UInt64
    public let activeVideoGraceSeconds: TimeInterval
    private let isActiveCaptureRunning: @Sendable () -> Bool

    public init(
        retryDelaysMilliseconds: [UInt64] = [20, 30, 50, 75, 100, 150, 250, 400, 600, 800, 1_000, 1_000, 1_000, 1_000],
        stabilityProbeMilliseconds: UInt64 = 40,
        videoProbeMilliseconds: UInt64 = 150,
        activeVideoGraceSeconds: TimeInterval = 5.0,
        isActiveCaptureRunning: @escaping @Sendable () -> Bool = { StabilityReader.defaultIsScreencaptureProcessRunning() }
    ) {
        self.retryDelaysNanoseconds = retryDelaysMilliseconds.map { $0 * 1_000_000 }
        self.stabilityProbeNanoseconds = stabilityProbeMilliseconds * 1_000_000
        self.videoProbeNanoseconds = videoProbeMilliseconds * 1_000_000
        self.activeVideoGraceSeconds = max(0, activeVideoGraceSeconds)
        self.isActiveCaptureRunning = isActiveCaptureRunning
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

    /// Classifies whether a staged video is still actively recording, incomplete/corrupt, or finalized and ready.
    public func readCompleteVideo(at url: URL) async -> (readiness: VideoReadiness, artifact: CapturedVideoArtifact?) {
        let ext = url.pathExtension.lowercased()
        guard SupportedMedia.isVideo(extension: ext),
              FileManager.default.fileExists(atPath: url.path) else {
            return (.incomplete, nil)
        }

        let contentType = SupportedMedia.contentType(forExtension: ext)
        let inspection = await inspectPlayableVideo(at: url)

        let sizeBefore = fileSize(at: url)
        if videoProbeNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: videoProbeNanoseconds)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (.incomplete, nil)
        }
        let sizeAfter = fileSize(at: url)

        if sizeAfter != sizeBefore {
            return (.inProgress, nil)
        }

        if inspection.playable, sizeAfter > 0 {
            let postStableInspection = await inspectPlayableVideo(at: url)
            if postStableInspection.playable {
                let thumbnailData = await extractThumbnailPNGData(
                    at: url,
                    durationSeconds: postStableInspection.durationSeconds
                )
                let artifact = CapturedVideoArtifact(
                    sourceURL: url,
                    contentType: contentType,
                    thumbnailPNGData: thumbnailData,
                    durationSeconds: postStableInspection.durationSeconds
                )
                return (.ready, artifact)
            }
        }

        if isActiveCaptureRunning() || isRecentlyModified(at: url, within: activeVideoGraceSeconds) {
            return (.inProgress, nil)
        }

        return (.incomplete, nil)
    }

    /// Evaluates video readiness without constructing a full preview artifact.
    public func checkVideoReadiness(at url: URL) async -> VideoReadiness {
        await readCompleteVideo(at: url).readiness
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

    private func isRecentlyModified(at url: URL, within seconds: TimeInterval) -> Bool {
        guard seconds > 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) < seconds
    }

    private func inspectPlayableVideo(at url: URL) async -> (playable: Bool, durationSeconds: Double?) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        guard let playable = try? await asset.load(.isPlayable), playable else {
            return (false, nil)
        }
        let tracks = (try? await asset.load(.tracks)) ?? []
        guard !tracks.isEmpty else {
            return (false, nil)
        }
        let duration = try? await asset.load(.duration)
        let seconds = duration.map { CMTimeGetSeconds($0) }
        let validDuration = (seconds != nil && seconds!.isFinite && seconds! > 0) ? seconds : nil
        return (validDuration != nil, validDuration)
    }

    private func extractThumbnailPNGData(at url: URL, durationSeconds: Double?) async -> Data? {
        let asset = AVURLAsset(url: url)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard !videoTracks.isEmpty else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 816, height: 592)

        let targetSeconds: Double
        if let durationSeconds, durationSeconds > 0 {
            targetSeconds = min(0.2, durationSeconds * 0.1)
        } else {
            targetSeconds = 0
        }
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)

        if let cgImage = try? await generator.image(at: targetTime).image {
            return Self.encodePNG(cgImage: cgImage)
        }
        if targetTime != .zero, let fallbackImage = try? await generator.image(at: .zero).image {
            return Self.encodePNG(cgImage: fallbackImage)
        }
        return nil
    }

    private static func encodePNG(cgImage: CGImage) -> Data? {
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return output as Data
    }

    /// Detects whether macOS's `screencapture` CLI process is currently alive (e.g. interactive Cmd+Shift+5 recording).
    public static func defaultIsScreencaptureProcessRunning() -> Bool {
        let estimatedBytes = proc_listallpids(nil, 0)
        guard estimatedBytes > 0 else { return false }

        let capacity = max(Int(estimatedBytes) / MemoryLayout<pid_t>.size + 64, 512)
        var pids = [pid_t](repeating: 0, count: capacity)
        let writtenBytes = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard writtenBytes > 0 else { return false }

        let count = Int(writtenBytes) / MemoryLayout<pid_t>.size
        for index in 0..<count where pids[index] > 0 {
            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let len = proc_name(pids[index], &nameBuffer, UInt32(nameBuffer.count))
            guard len > 0 else { continue }
            let end = nameBuffer.firstIndex(of: 0) ?? nameBuffer.count
            let processName = String(decoding: nameBuffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if processName == "screencapture" {
                return true
            }
        }
        return false
    }
}
