import Foundation
import Testing
@testable import SnapClipCore

final class InMemoryDefaultsStore: DefaultsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(initial: [String: Any] = [:]) {
        self.values = initial
    }

    func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    func string(forKey key: String) -> String? {
        lock.withLock { values[key] as? String }
    }

    func bool(forKey key: String) -> Bool {
        lock.withLock {
            if let b = values[key] as? Bool { return b }
            if let i = values[key] as? Int { return i != 0 }
            return false
        }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock {
            values[key] = value
        }
    }

    func removeObject(forKey key: String) {
        _ = lock.withLock {
            values.removeValue(forKey: key)
        }
    }
}

@Suite("ConfigAndDefaults")
struct ConfigAndDefaultsTests {
    @Test("Loads partial JSON config while keeping default values for omitted fields")
    func loadsPartialConfig() throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent("config.json")
        let partialJSON = """
        {
          "keepFile": false,
          "previewAutoDismissSeconds": 3.0
        }
        """
        try Data(partialJSON.utf8).write(to: configPath)

        let loaded = try SnapClipConfig.load(from: configPath.path, homeDirectory: dir.path)
        #expect(loaded.keepFile == false)
        #expect(loaded.previewAutoDismissSeconds == 3.0)
        #expect(loaded.showFloatingPreview == true)
        #expect(loaded.destinationURL(homeDirectory: dir.path).path == dir.appendingPathComponent("Desktop").path)
    }

    @Test("Install backs up original defaults once and uninstall restores exact state")
    func reversibleInstallAndUninstall() throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let store = InMemoryDefaultsStore(initial: [
            "location": "/tmp/original-shots",
            "show-thumbnail": true,
            "target-screenrecording": "clipboard"
        ])
        let config = SnapClipConfig()
        let manager = SystemDefaultsManager(store: store, homeDirectory: home.path)

        let firstBackup = try manager.applyInstallDefaults(config: config)
        let secondBackup = try manager.applyInstallDefaults(config: config)

        #expect(firstBackup == true)
        #expect(secondBackup == false)
        #expect(store.string(forKey: "location-screenshot") == config.stagingURL(homeDirectory: home.path).path)
        #expect(store.string(forKey: "location-screenrecording") == config.stagingURL(homeDirectory: home.path).path)
        #expect(store.bool(forKey: "show-thumbnail") == false)
        #expect(store.string(forKey: "target-screenshot") == "file")
        #expect(store.string(forKey: "target-screenrecording") == "file")

        let restored = try manager.restoreDefaultsFromBackup(config: config)
        #expect(restored == true)
        #expect(store.string(forKey: "location") == "/tmp/original-shots")
        #expect(store.bool(forKey: "show-thumbnail") == true)
        #expect(store.string(forKey: "target-screenrecording") == "clipboard")
        #expect(store.object(forKey: "location-screenshot") == nil)
        #expect(store.object(forKey: "target-screenshot") == nil)
    }

    @Test("Doctor reports healthy when configured and flags drift, backlog, and conflicting agent")
    func doctorDetectsHealthyAndDriftedStates() throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let bin = home.appendingPathComponent("snapclip")
        try Data("#!/bin/sh\n".utf8).write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

        let store = InMemoryDefaultsStore()
        let config = SnapClipConfig()
        let manager = SystemDefaultsManager(store: store, homeDirectory: home.path)
        try manager.applyInstallDefaults(config: config)

        let healthy = manager.buildDoctorReport(
            config: config,
            binaryPath: bin.path,
            launchAgentLoaded: true
        )
        #expect(healthy.healthy == true)

        // Drift location and leave a file in staging
        store.set("/tmp/elsewhere", forKey: "location-screenshot")
        store.set("/tmp/elsewhere-video", forKey: "location-screenrecording")
        try Data("x".utf8).write(to: config.stagingURL(homeDirectory: home.path).appendingPathComponent("stuck.png"))

        let unhealthy = manager.buildDoctorReport(
            config: config,
            binaryPath: bin.path,
            launchAgentLoaded: true,
            conflictingAgentLabel: "com.example.other-guard",
            conflictingAgentLoaded: true
        )
        #expect(unhealthy.healthy == false)
        #expect(unhealthy.stuckFilesInStaging == 1)
        #expect(unhealthy.checks.first(where: { $0.name == "screencapture_location" })?.ok == false)
        #expect(unhealthy.checks.first(where: { $0.name == "screencapture_recording_location" })?.ok == false)
        #expect(unhealthy.checks.first(where: { $0.name == "conflicting_agent" })?.ok == false)
    }

    @Test("Install respects watchScreenRecordings=false by sending recordings directly to destination")
    func installWithWatchRecordingsDisabled() throws {
        let home = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let store = InMemoryDefaultsStore()
        let config = SnapClipConfig(watchScreenRecordings: false)
        let manager = SystemDefaultsManager(store: store, homeDirectory: home.path)
        try manager.applyInstallDefaults(config: config)

        #expect(store.string(forKey: "location-screenshot") == config.stagingURL(homeDirectory: home.path).path)
        #expect(store.string(forKey: "location-screenrecording") == config.destinationURL(homeDirectory: home.path).path)
    }

    @Test("Executable resolver handles PATH invocations and Homebrew opt symlinks cleanly")
    func executablePathResolution() throws {
        let fromPATH = SystemDefaultsManager.resolveLaunchAgentExecutablePath(
            argumentZero: "snapclip",
            environmentPATH: "/usr/bin:/tmp/snapclip-home/.local/bin",
            fallbackMachOPath: "/tmp/snapclip-home/.local/bin/real-snapclip",
            currentDirectory: "/tmp",
            isExecutable: { $0 == "/tmp/snapclip-home/.local/bin/snapclip" }
        )
        #expect(fromPATH == "/tmp/snapclip-home/.local/bin/snapclip")

        let stableBrew = SystemDefaultsManager.resolveLaunchAgentExecutablePath(
            argumentZero: "/opt/homebrew/Cellar/snapclip/0.1.0/bin/snapclip",
            environmentPATH: nil,
            fallbackMachOPath: nil,
            currentDirectory: "/tmp",
            isExecutable: { $0 == "/opt/homebrew/opt/snapclip/bin/snapclip" }
        )
        #expect(stableBrew == "/opt/homebrew/opt/snapclip/bin/snapclip")
    }

    @Test("ProcessFileLock rejects concurrent lock acquisition until released")
    func processLockExclusivity() throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lock1 = ProcessFileLock(stateDirectory: dir)
        let lock2 = ProcessFileLock(stateDirectory: dir)

        try lock1.acquire()
        var secondFailed = false
        do {
            try lock2.acquire()
        } catch {
            secondFailed = true
        }
        #expect(secondFailed == true)

        lock1.release()
        try lock2.acquire()
        lock2.release()
    }

    @Test("Donate report resolves GitHub Sponsors URL and rejects unknown channels")
    func donateReportAndChannelValidation() throws {
        let report = try SnapClipSupport.buildReport(channel: "sponsors", opened: true)
        #expect(report.url == SnapClipSupport.githubSponsorsURL)
        #expect(report.githubSponsors == SnapClipSupport.githubSponsorsURL)
        #expect(report.opened == true)
        #expect(report.channels.first?.id == "github")

        var rejectedUnknown = false
        do {
            _ = try SnapClipSupport.buildReport(channel: "unknown")
        } catch let error as SupportError {
            rejectedUnknown = (error == .unknownChannel("unknown"))
        }
        #expect(rejectedUnknown == true)
    }
}
