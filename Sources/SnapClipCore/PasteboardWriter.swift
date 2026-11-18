import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes encoded image payloads and file URLs to the system clipboard (or a test double).
public protocol PasteboardWriting: Sendable {
    func writeImage(data: Data, contentType: UTType, includeTiff: Bool) async -> Bool
    func writeFileURL(_ url: URL) async -> Bool
}

public extension PasteboardWriting {
    func writeFileURL(_ url: URL) async -> Bool { false }
}

/// Encoded representations ready to attach atomically to an `NSPasteboardItem`.
public struct EncodedPasteboardPayload: Sendable {
    public let pngData: Data
    public let tiffData: Data?

    public init(pngData: Data, tiffData: Data?) {
        self.pngData = pngData
        self.tiffData = tiffData
    }
}

/// Pure encoder converting any ImageIO-supported source format into valid PNG and optional LZW-compressed TIFF.
public enum PasteboardImageEncoder {
    public static func encode(
        data: Data,
        contentType: UTType,
        includeTiff: Bool
    ) -> EncodedPasteboardPayload? {
        let pngData: Data?
        if contentType == .png {
            pngData = data
        } else {
            pngData = transcodeToPNG(data)
        }
        guard let validPNG = pngData else { return nil }

        var tiffData: Data?
        if includeTiff {
            tiffData = encodeCompressedTIFF(fromPNGOrImageData: validPNG)
        }
        return EncodedPasteboardPayload(pngData: validPNG, tiffData: tiffData)
    }

    public static func transcodeToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    public static func encodeCompressedTIFF(fromPNGOrImageData data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.tiffRepresentation(using: .lzw, factor: 0) ?? rep.tiffRepresentation
    }
}

/// Writes screenshot images atomically onto `NSPasteboard.general`.
public final class SystemPasteboardWriter: PasteboardWriting {
    public init() {}

    public func writeImage(data: Data, contentType: UTType, includeTiff: Bool) async -> Bool {
        guard let payload = PasteboardImageEncoder.encode(
            data: data,
            contentType: contentType,
            includeTiff: includeTiff
        ) else {
            return false
        }

        return await MainActor.run {
            let pb = NSPasteboard.general
            let item = NSPasteboardItem()
            var wrote = item.setData(payload.pngData, forType: .png)
            if let tiffData = payload.tiffData {
                wrote = item.setData(tiffData, forType: .tiff) || wrote
            }
            guard wrote else { return false }
            pb.clearContents()
            return pb.writeObjects([item])
        }
    }

    public func writeFileURL(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return await MainActor.run {
            Self.writeFileURL(url, to: .general)
        }
    }

    @MainActor
    static func writeFileURL(_ url: URL, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }
}
