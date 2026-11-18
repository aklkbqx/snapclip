import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Supported media extensions monitored by SnapClip.
public enum SupportedMedia {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp"]
    public static let videoExtensions: Set<String> = ["mov", "mp4"]

    public static func isImage(extension ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }

    public static func isVideo(extension ext: String) -> Bool {
        videoExtensions.contains(ext.lowercased())
    }

    public static func contentType(forExtension ext: String) -> UTType {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic": return .heic
        case "tiff", "tif": return .tiff
        case "webp": return .webP
        case "mov": return .quickTimeMovie
        case "mp4": return .mpeg4Movie
        default: return UTType(filenameExtension: ext) ?? .data
        }
    }
}

/// Immutable representation of a finalized screenshot ready for processing and sinks.
public struct CapturedArtifact: Sendable {
    public let sourceURL: URL
    public let fileName: String
    public let fileExtension: String
    public let data: Data
    public let contentType: UTType
    public let sha256: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let capturedAt: Date

    public init(
        sourceURL: URL,
        data: Data,
        contentType: UTType,
        pixelWidth: Int,
        pixelHeight: Int,
        capturedAt: Date = Date()
    ) {
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.fileExtension = sourceURL.pathExtension.lowercased()
        self.data = data
        self.contentType = contentType
        self.sha256 = Self.sha256Hex(of: data)
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capturedAt = capturedAt
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Visual presentation mode for the floating corner preview card.
public enum PreviewMediaKind: Equatable, Sendable {
    case image
    case video(durationSeconds: Double?)
}

/// Immutable representation of a finalized screen recording ready for placement and preview presentation.
public struct CapturedVideoArtifact: Sendable {
    public let sourceURL: URL
    public let fileName: String
    public let fileExtension: String
    public let contentType: UTType
    public let thumbnailPNGData: Data?
    public let durationSeconds: Double?
    public let capturedAt: Date

    public init(
        sourceURL: URL,
        contentType: UTType,
        thumbnailPNGData: Data?,
        durationSeconds: Double?,
        capturedAt: Date = Date()
    ) {
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.fileExtension = sourceURL.pathExtension.lowercased()
        self.contentType = contentType
        self.thumbnailPNGData = thumbnailPNGData
        self.durationSeconds = durationSeconds
        self.capturedAt = capturedAt
    }
}

/// Result recorded after processing a single file in staging.
public enum CaptureProcessingResult: Equatable, Sendable {
    case processedImage(fileName: String, copiedToClipboard: Bool, destinationPath: String?)
    case movedRecording(fileName: String, destinationPath: String)
    case skippedIncomplete(fileName: String)
    case ignored(fileName: String)
}

/// Insertion-ordered cache bounded to a maximum capacity so long-running daemons do not leak RAM.
public struct BoundedKeyValueCache<Key: Hashable & Sendable, Value: Equatable & Sendable>: Sendable {
    private let capacity: Int
    private var order: [Key] = []
    private var storage: [Key: Value] = [:]

    public init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
    }

    public subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let value = newValue {
                if storage[key] == nil {
                    order.append(key)
                }
                storage[key] = value
                trimIfNeeded()
            } else {
                storage.removeValue(forKey: key)
                order.removeAll { $0 == key }
            }
        }
    }

    public var count: Int { storage.count }

    private mutating func trimIfNeeded() {
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }
}

/// Simple logger abstraction for unit-test capture and structured daemon output.
public protocol SnapClipLogging: Sendable {
    func log(_ message: String)
}

/// Default stdout logger with ISO-8601 timestamps flushed immediately for LaunchAgent log files.
public struct StandardLogger: SnapClipLogging {
    public init() {}

    public func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] [snapclip] \(message)")
        fflush(stdout)
    }
}
