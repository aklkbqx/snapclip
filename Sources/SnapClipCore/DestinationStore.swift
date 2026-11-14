import Foundation

/// Manages chronological discovery, collision-safe placement, and trash operations for staged media files.
public struct DestinationStore: Sendable {
    public init() {}

    /// Lists supported media URLs in `directory` ordered oldest-first so rapid captures preserve final order.
    public func sortedMediaURLs(in directory: URL, includeVideos: Bool = true) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let filtered = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            if SupportedMedia.isImage(extension: ext) { return true }
            return includeVideos && SupportedMedia.isVideo(extension: ext)
        }

        return filtered.sorted { lhs, rhs in
            let lDate = captureTimestamp(for: lhs)
            let rDate = captureTimestamp(for: rhs)
            if lDate != rDate {
                return lDate < rDate
            }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
    }

    /// Resolves a collision-safe destination path in `directory`, checking `(2)...(99)` and falling back to a unique timestamp suffix.
    public func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(fileName)
        let fm = FileManager.default
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        for idx in 2...99 {
            let numbered = ext.isEmpty ? "\(base) (\(idx))" : "\(base) (\(idx)).\(ext)"
            let numberedURL = directory.appendingPathComponent(numbered)
            if !fm.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
        }

        let suffix = UUID().uuidString.prefix(8)
        let fallbackName = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
        return directory.appendingPathComponent(fallbackName)
    }

    /// Moves a staged file to `directory` safely, including cross-volume atomic fallback.
    public func moveToDestination(from sourceURL: URL, toDirectory directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destURL = uniqueDestinationURL(for: sourceURL.lastPathComponent, in: directory)
        do {
            try fm.moveItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            // Cross-volume moves can fail if staging and destination reside on different filesystems.
            let tempURL = directory.appendingPathComponent(".snapclip-tmp-\(UUID().uuidString)")
            try fm.copyItem(at: sourceURL, to: tempURL)
            do {
                try fm.moveItem(at: tempURL, to: destURL)
                try? fm.removeItem(at: sourceURL)
                return destURL
            } catch {
                try? fm.removeItem(at: tempURL)
                throw error
            }
        }
    }

    /// Moves a file to the user's macOS Trash instead of permanently unlinking it.
    @discardableResult
    public func trashFile(at url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private func captureTimestamp(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }
}
