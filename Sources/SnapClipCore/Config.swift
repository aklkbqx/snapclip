import Foundation

/// Runtime configuration for SnapClip watcher, pasteboard, destination, and floating preview.
public struct SnapClipConfig: Codable, Equatable, Sendable {
    public var stagingDirectory: String
    public var destinationDirectory: String
    public var stateDirectory: String
    public var logPath: String
    public var keepFile: Bool
    public var showFloatingPreview: Bool
    public var previewAutoDismissSeconds: Double
    public var previewHoverDismissSeconds: Double
    public var includeTiffOnPasteboard: Bool
    public var maxLogSizeBytes: Int
    public var watchScreenRecordings: Bool
    public var copyScreenRecordingsToClipboard: Bool

    public static let defaultConfigPath = "~/.config/snapclip/config.json"

    public init(
        stagingDirectory: String = "~/.local/state/snapclip/staging",
        destinationDirectory: String = "~/Desktop",
        stateDirectory: String = "~/.local/state/snapclip",
        logPath: String = "~/Library/Logs/snapclip.log",
        keepFile: Bool = true,
        showFloatingPreview: Bool = true,
        previewAutoDismissSeconds: Double = 4.5,
        previewHoverDismissSeconds: Double = 2.5,
        includeTiffOnPasteboard: Bool = true,
        maxLogSizeBytes: Int = 1_048_576,
        watchScreenRecordings: Bool = true,
        copyScreenRecordingsToClipboard: Bool = true
    ) {
        self.stagingDirectory = stagingDirectory
        self.destinationDirectory = destinationDirectory
        self.stateDirectory = stateDirectory
        self.logPath = logPath
        self.keepFile = keepFile
        self.showFloatingPreview = showFloatingPreview
        self.previewAutoDismissSeconds = previewAutoDismissSeconds
        self.previewHoverDismissSeconds = previewHoverDismissSeconds
        self.includeTiffOnPasteboard = includeTiffOnPasteboard
        self.maxLogSizeBytes = maxLogSizeBytes
        self.watchScreenRecordings = watchScreenRecordings
        self.copyScreenRecordingsToClipboard = copyScreenRecordingsToClipboard
    }

    /// Loads config from `path` (if present), filling any omitted keys with defaults.
    public static func load(
        from path: String? = nil,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) throws -> SnapClipConfig {
        let resolved = expandPath(path ?? defaultConfigPath, homeDirectory: homeDirectory)
        let url = URL(fileURLWithPath: resolved)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SnapClipConfig()
        }
        let data = try Data(contentsOf: url)
        let partial = try JSONDecoder().decode(PartialConfig.self, from: data)
        let defaults = SnapClipConfig()
        return SnapClipConfig(
            stagingDirectory: partial.stagingDirectory ?? defaults.stagingDirectory,
            destinationDirectory: partial.destinationDirectory ?? defaults.destinationDirectory,
            stateDirectory: partial.stateDirectory ?? defaults.stateDirectory,
            logPath: partial.logPath ?? defaults.logPath,
            keepFile: partial.keepFile ?? defaults.keepFile,
            showFloatingPreview: partial.showFloatingPreview ?? defaults.showFloatingPreview,
            previewAutoDismissSeconds: max(0.5, partial.previewAutoDismissSeconds ?? defaults.previewAutoDismissSeconds),
            previewHoverDismissSeconds: max(0.5, partial.previewHoverDismissSeconds ?? defaults.previewHoverDismissSeconds),
            includeTiffOnPasteboard: partial.includeTiffOnPasteboard ?? defaults.includeTiffOnPasteboard,
            maxLogSizeBytes: max(16_384, partial.maxLogSizeBytes ?? defaults.maxLogSizeBytes),
            watchScreenRecordings: partial.watchScreenRecordings ?? defaults.watchScreenRecordings,
            copyScreenRecordingsToClipboard: partial.copyScreenRecordingsToClipboard ?? defaults.copyScreenRecordingsToClipboard
        )
    }

    /// Persists the configuration as formatted JSON, creating parent directories if needed.
    public func save(
        to path: String? = nil,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) throws {
        let resolved = Self.expandPath(path ?? Self.defaultConfigPath, homeDirectory: homeDirectory)
        let url = URL(fileURLWithPath: resolved)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public func stagingURL(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> URL {
        URL(fileURLWithPath: Self.expandPath(stagingDirectory, homeDirectory: homeDirectory), isDirectory: true)
    }

    public func destinationURL(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> URL {
        URL(fileURLWithPath: Self.expandPath(destinationDirectory, homeDirectory: homeDirectory), isDirectory: true)
    }

    public func stateURL(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> URL {
        URL(fileURLWithPath: Self.expandPath(stateDirectory, homeDirectory: homeDirectory), isDirectory: true)
    }

    public func resolvedLogURL(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> URL {
        URL(fileURLWithPath: Self.expandPath(logPath, homeDirectory: homeDirectory), isDirectory: false)
    }

    /// Expands a leading `~` or `~/` using the provided home directory.
    public static func expandPath(_ raw: String, homeDirectory: String) -> String {
        if raw == "~" { return homeDirectory }
        if raw.hasPrefix("~/") {
            let suffix = String(raw.dropFirst(2))
            return URL(fileURLWithPath: homeDirectory).appendingPathComponent(suffix).path
        }
        return raw
    }
}

private struct PartialConfig: Codable {
    var stagingDirectory: String?
    var destinationDirectory: String?
    var stateDirectory: String?
    var logPath: String?
    var keepFile: Bool?
    var showFloatingPreview: Bool?
    var previewAutoDismissSeconds: Double?
    var previewHoverDismissSeconds: Double?
    var includeTiffOnPasteboard: Bool?
    var maxLogSizeBytes: Int?
    var watchScreenRecordings: Bool?
    var copyScreenRecordingsToClipboard: Bool?
}
