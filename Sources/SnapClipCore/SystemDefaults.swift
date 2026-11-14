import Foundation

/// Abstraction over macOS UserDefaults so setup, backup, restore, and doctor logic can be unit-tested cleanly.
public protocol DefaultsStoring: Sendable {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

/// Real UserDefaults-backed store targeting `com.apple.screencapture`.
public final class SuiteDefaultsStore: DefaultsStoring, @unchecked Sendable {
    private let suiteName: String
    private let defaults: UserDefaults

    public init(suiteName: String = SystemDefaultsManager.screencaptureDomain) {
        self.suiteName = suiteName
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }

    public func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        CFPreferencesAppSynchronize(suiteName as CFString)
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
        CFPreferencesAppSynchronize(suiteName as CFString)
    }
}

/// Snapshot of pre-existing `com.apple.screencapture` preferences stored for reversible uninstall.
public struct ScreencaptureDefaultsBackup: Codable, Equatable, Sendable {
    public var location: String?
    public var locationScreenshot: String?
    public var locationScreenRecording: String?
    public var showThumbnail: Bool?
    public var target: String?
    public var targetScreenshot: String?
    public var targetScreenRecording: String?
    public var capturedAtISO8601: String

    public init(
        location: String?,
        locationScreenshot: String?,
        locationScreenRecording: String?,
        showThumbnail: Bool?,
        target: String?,
        targetScreenshot: String?,
        targetScreenRecording: String? = nil,
        capturedAtISO8601: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.location = location
        self.locationScreenshot = locationScreenshot
        self.locationScreenRecording = locationScreenRecording
        self.showThumbnail = showThumbnail
        self.target = target
        self.targetScreenshot = targetScreenshot
        self.targetScreenRecording = targetScreenRecording
        self.capturedAtISO8601 = capturedAtISO8601
    }
}

/// Structured status/doctor check item.
public struct DiagnosticCheck: Codable, Equatable, Sendable {
    public let name: String
    public let ok: Bool
    public let detail: String

    public init(name: String, ok: Bool, detail: String) {
        self.name = name
        self.ok = ok
        self.detail = detail
    }
}

/// Full diagnostic report returned by `snapclip status` and `snapclip doctor`.
public struct DoctorReport: Codable, Equatable, Sendable {
    public let healthy: Bool
    public let stagingPath: String
    public let destinationPath: String
    public let launchAgentLabel: String
    public let launchAgentLoaded: Bool
    public let conflictingAgentLabel: String?
    public let conflictingAgentLoaded: Bool
    public let stuckFilesInStaging: Int
    public let checks: [DiagnosticCheck]

    public init(
        healthy: Bool,
        stagingPath: String,
        destinationPath: String,
        launchAgentLabel: String,
        launchAgentLoaded: Bool,
        conflictingAgentLabel: String? = nil,
        conflictingAgentLoaded: Bool = false,
        stuckFilesInStaging: Int,
        checks: [DiagnosticCheck]
    ) {
        self.healthy = healthy
        self.stagingPath = stagingPath
        self.destinationPath = destinationPath
        self.launchAgentLabel = launchAgentLabel
        self.launchAgentLoaded = launchAgentLoaded
        self.conflictingAgentLabel = conflictingAgentLabel
        self.conflictingAgentLoaded = conflictingAgentLoaded
        self.stuckFilesInStaging = stuckFilesInStaging
        self.checks = checks
    }
}

/// Handles reversible configuration of `com.apple.screencapture`, LaunchAgent plist generation, executable resolution, and diagnostics.
public struct SystemDefaultsManager: Sendable {
    public static let screencaptureDomain = "com.apple.screencapture"
    public static let launchAgentLabel = "com.snapclip.agent"

    private let store: any DefaultsStoring
    private let homeDirectory: String

    public init(
        store: any DefaultsStoring = SuiteDefaultsStore(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.store = store
        self.homeDirectory = homeDirectory
    }

    public func backupFileURL(config: SnapClipConfig) -> URL {
        config.stateURL(homeDirectory: homeDirectory).appendingPathComponent("backup-defaults.json")
    }

    public func launchAgentPlistURL(label: String = Self.launchAgentLabel) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Resolves a durable binary path for LaunchAgent plists, keeping Homebrew `opt/` symlinks instead of Cellar version paths.
    public static func resolveLaunchAgentExecutablePath(
        argumentZero: String,
        environmentPATH: String?,
        fallbackMachOPath: String?,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        resolveLaunchAgentExecutablePath(
            argumentZero: argumentZero,
            environmentPATH: environmentPATH,
            fallbackMachOPath: fallbackMachOPath,
            currentDirectory: currentDirectory,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    static func resolveLaunchAgentExecutablePath(
        argumentZero: String,
        environmentPATH: String?,
        fallbackMachOPath: String?,
        currentDirectory: String,
        isExecutable: (String) -> Bool
    ) -> String {
        let resolvedCandidate: String

        if argumentZero.contains("/") {
            resolvedCandidate = normalizeAbsolutePath(argumentZero, relativeTo: currentDirectory)
        } else if let pathEnv = environmentPATH,
                  let foundOnPath = findExecutableInPATH(named: argumentZero, pathValue: pathEnv, isExecutable: isExecutable) {
            resolvedCandidate = foundOnPath
        } else if let machoPath = fallbackMachOPath, !machoPath.isEmpty {
            resolvedCandidate = URL(fileURLWithPath: machoPath).standardizedFileURL.path
        } else {
            resolvedCandidate = normalizeAbsolutePath(argumentZero, relativeTo: currentDirectory)
        }

        if let stableHomebrew = stabilizeHomebrewPath(resolvedCandidate, fileExists: isExecutable) {
            return stableHomebrew
        }
        return resolvedCandidate
    }

    /// Saves pre-SnapClip `com.apple.screencapture` defaults (without overwriting an existing backup) and applies SnapClip settings.
    @discardableResult
    public func applyInstallDefaults(config: SnapClipConfig) throws -> Bool {
        let fm = FileManager.default
        let stagingDir = config.stagingURL(homeDirectory: homeDirectory)
        let destDir = config.destinationURL(homeDirectory: homeDirectory)
        let stateDir = config.stateURL(homeDirectory: homeDirectory)
        let logURL = config.resolvedLogURL(homeDirectory: homeDirectory)

        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backupURL = backupFileURL(config: config)
        var createdBackup = false
        if !fm.fileExists(atPath: backupURL.path) {
            let backup = ScreencaptureDefaultsBackup(
                location: store.string(forKey: "location"),
                locationScreenshot: store.string(forKey: "location-screenshot"),
                locationScreenRecording: store.string(forKey: "location-screenrecording"),
                showThumbnail: store.object(forKey: "show-thumbnail") != nil ? store.bool(forKey: "show-thumbnail") : nil,
                target: store.string(forKey: "target"),
                targetScreenshot: store.string(forKey: "target-screenshot"),
                targetScreenRecording: store.string(forKey: "target-screenrecording")
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(backup).write(to: backupURL, options: .atomic)
            createdBackup = true
        }

        store.set(stagingDir.path, forKey: "location")
        store.set(stagingDir.path, forKey: "location-screenshot")
        store.set(destDir.path, forKey: "location-screenrecording")
        store.set(false, forKey: "show-thumbnail")
        store.set("file", forKey: "target")
        store.set("file", forKey: "target-screenshot")
        store.set("file", forKey: "target-screenrecording")
        return createdBackup
    }

    /// Restores `com.apple.screencapture` preferences from the backup created during `install`.
    @discardableResult
    public func restoreDefaultsFromBackup(config: SnapClipConfig) throws -> Bool {
        let fm = FileManager.default
        let backupURL = backupFileURL(config: config)
        guard fm.fileExists(atPath: backupURL.path) else {
            return false
        }
        let data = try Data(contentsOf: backupURL)
        let backup = try JSONDecoder().decode(ScreencaptureDefaultsBackup.self, from: data)

        restoreOrRemoveString(backup.location, forKey: "location")
        restoreOrRemoveString(backup.locationScreenshot, forKey: "location-screenshot")
        restoreOrRemoveString(backup.locationScreenRecording, forKey: "location-screenrecording")
        restoreOrRemoveString(backup.target, forKey: "target")
        restoreOrRemoveString(backup.targetScreenshot, forKey: "target-screenshot")
        restoreOrRemoveString(backup.targetScreenRecording, forKey: "target-screenrecording")
        if let thumb = backup.showThumbnail {
            store.set(thumb, forKey: "show-thumbnail")
        } else {
            store.removeObject(forKey: "show-thumbnail")
        }

        try? fm.removeItem(at: backupURL)
        return true
    }

    /// Renders a valid XML LaunchAgent property list invoking `binaryPath run`.
    public func renderLaunchAgentPlist(binaryPath: String, config: SnapClipConfig) throws -> Data {
        let logPath = config.resolvedLogURL(homeDirectory: homeDirectory).path
        let plistDict: [String: Any] = [
            "Label": Self.launchAgentLabel,
            "ProgramArguments": [binaryPath, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        return try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
    }

    /// Runs health checks across staging/destination paths, `com.apple.screencapture` defaults, and LaunchAgent status.
    public func buildDoctorReport(
        config: SnapClipConfig,
        binaryPath: String,
        launchAgentLoaded: Bool,
        conflictingAgentLabel: String? = nil,
        conflictingAgentLoaded: Bool = false
    ) -> DoctorReport {
        let fm = FileManager.default
        let stagingDir = config.stagingURL(homeDirectory: homeDirectory)
        let destDir = config.destinationURL(homeDirectory: homeDirectory)

        let stagingExists = fm.fileExists(atPath: stagingDir.path)
        let destExists = !config.keepFile || fm.fileExists(atPath: destDir.path)
        let stuckCount = ((try? fm.contentsOfDirectory(atPath: stagingDir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .count

        let configuredLocation = store.string(forKey: "location-screenshot") ?? store.string(forKey: "location")
        let locationOK = configuredLocation == stagingDir.path
        let thumbnailDisabled = store.object(forKey: "show-thumbnail") != nil && !store.bool(forKey: "show-thumbnail")
        let targetOK = (store.string(forKey: "target-screenshot") ?? store.string(forKey: "target") ?? "file") == "file"
        let binaryExists = fm.isExecutableFile(atPath: binaryPath)

        var checks: [DiagnosticCheck] = [
            DiagnosticCheck(
                name: "binary",
                ok: binaryExists,
                detail: binaryExists ? binaryPath : "Missing executable at \(binaryPath)"
            ),
            DiagnosticCheck(
                name: "staging_dir",
                ok: stagingExists,
                detail: stagingExists ? stagingDir.path : "Missing directory \(stagingDir.path)"
            ),
            DiagnosticCheck(
                name: "destination_dir",
                ok: destExists,
                detail: config.keepFile ? destDir.path : "clipboard-only mode (keepFile=false)"
            ),
            DiagnosticCheck(
                name: "screencapture_location",
                ok: locationOK,
                detail: locationOK ? stagingDir.path : "Expected \(stagingDir.path), got \(configuredLocation ?? "<unset>")"
            ),
            DiagnosticCheck(
                name: "screencapture_thumbnail_delay",
                ok: thumbnailDisabled,
                detail: thumbnailDisabled ? "show-thumbnail=0 (instant flush)" : "show-thumbnail is enabled (causes 5s macOS delay)"
            ),
            DiagnosticCheck(
                name: "screencapture_target",
                ok: targetOK,
                detail: targetOK ? "target=file" : "target is not 'file'"
            ),
            DiagnosticCheck(
                name: "launch_agent",
                ok: launchAgentLoaded,
                detail: launchAgentLoaded ? "\(Self.launchAgentLabel) running" : "\(Self.launchAgentLabel) not loaded"
            ),
            DiagnosticCheck(
                name: "staging_backlog",
                ok: stuckCount == 0,
                detail: stuckCount == 0 ? "0 pending files" : "\(stuckCount) file(s) waiting in staging"
            )
        ]

        if let conflictLabel = conflictingAgentLabel, !conflictLabel.isEmpty {
            checks.append(
                DiagnosticCheck(
                    name: "conflicting_agent",
                    ok: !conflictingAgentLoaded,
                    detail: conflictingAgentLoaded ? "\(conflictLabel) is still running alongside SnapClip" : "\(conflictLabel) is not loaded"
                )
            )
        }

        let healthy = checks.allSatisfy { $0.ok }
        return DoctorReport(
            healthy: healthy,
            stagingPath: stagingDir.path,
            destinationPath: destDir.path,
            launchAgentLabel: Self.launchAgentLabel,
            launchAgentLoaded: launchAgentLoaded,
            conflictingAgentLabel: conflictingAgentLabel,
            conflictingAgentLoaded: conflictingAgentLoaded,
            stuckFilesInStaging: stuckCount,
            checks: checks
        )
    }

    private func restoreOrRemoveString(_ value: String?, forKey key: String) {
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    private static func normalizeAbsolutePath(_ raw: String, relativeTo baseDir: String) -> String {
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL.path
        }
        let base = URL(fileURLWithPath: baseDir, isDirectory: true)
        return base.appendingPathComponent(raw).standardizedFileURL.path
    }

    private static func findExecutableInPATH(
        named name: String,
        pathValue: String,
        isExecutable: (String) -> Bool
    ) -> String? {
        for dir in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir), isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
                .path
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func stabilizeHomebrewPath(_ path: String, fileExists: (String) -> Bool) -> String? {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let cellarPrefix = "\(prefix)/Cellar/"
            guard path.hasPrefix(cellarPrefix) else { continue }
            let remainder = String(path.dropFirst(cellarPrefix.count))
            let parts = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            let formula = String(parts[0])
            let binaryName = String(parts.last ?? "")
            let optCandidate = "\(prefix)/opt/\(formula)/bin/\(binaryName)"
            if fileExists(optCandidate) {
                return optCandidate
            }
            let binCandidate = "\(prefix)/bin/\(binaryName)"
            if fileExists(binCandidate) {
                return binCandidate
            }
        }
        return nil
    }
}
