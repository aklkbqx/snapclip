import AppKit
import Foundation
import MachO
import SnapClipCore
import SnapClipUI

enum SnapClipVersion {
    static let current = "0.1.0"
}

@main
struct SnapClipCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        let flags = Array(args.dropFirst())

        do {
            switch command {
            case "run":
                try runDaemon(args: flags)
            case "install":
                try runInstall(args: flags)
            case "uninstall":
                try runUninstall()
            case "status":
                try runStatus(args: flags)
            case "doctor":
                try runDoctor(args: flags)
            case "config":
                try runConfig(args: flags)
            case "donate", "sponsor":
                try runDonate(args: flags)
            case "version", "--version", "-v":
                print("snapclip \(SnapClipVersion.current)")
            case "help", "--help", "-h":
                printUsage()
            default:
                fputs("Unknown command '\(command)'.\n\n", stderr)
                printUsage()
                exit(2)
            }
        } catch {
            fputs("snapclip error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runDaemon(args: [String]) throws {
        var configPath: String?
        var clipboardOnly = false
        var noPreview = false
        var idx = 0
        while idx < args.count {
            switch args[idx] {
            case "--config":
                idx += 1
                guard idx < args.count else {
                    throw CLIError.invalidArgument("--config requires a file path")
                }
                configPath = args[idx]
            case "--clipboard-only":
                clipboardOnly = true
            case "--no-preview":
                noPreview = true
            default:
                throw CLIError.invalidArgument("Unknown option for run: \(args[idx])")
            }
            idx += 1
        }

        var config = try SnapClipConfig.load(from: configPath)
        if clipboardOnly { config.keepFile = false }
        if noPreview { config.showFloatingPreview = false }

        let daemonLock = ProcessFileLock(stateDirectory: config.stateURL())
        try daemonLock.acquire()

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)

            let previewController = FloatingThumbnailController()
            let pipeline = SnapClipPipeline(
                config: config,
                pasteboardWriter: SystemPasteboardWriter(),
                previewPresenter: config.showFloatingPreview ? previewController : nil
            )
            let watcher = CaptureWatcher(config: config, pipeline: pipeline)

            do {
                try watcher.start()
            } catch {
                daemonLock.release()
                fputs("snapclip failed to start: \(error.localizedDescription)\n", stderr)
                exit(1)
            }

            let signalSources = installSignalHandlers {
                watcher.stop()
                daemonLock.release()
                app.terminate(nil)
            }
            withExtendedLifetime(signalSources) {
                app.run()
            }
            watcher.stop()
            daemonLock.release()
        }
    }

    private static func installSignalHandlers(onShutdown: @escaping @MainActor () -> Void) -> [DispatchSourceSignal] {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        return [SIGINT, SIGTERM].map { sig in
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    onShutdown()
                }
            }
            source.resume()
            return source
        }
    }

    private static func runInstall(args: [String]) throws {
        var noLoad = false
        var migrateLabels: [String] = []
        var idx = 0
        while idx < args.count {
            switch args[idx] {
            case "--no-load":
                noLoad = true
            case "--migrate-agent":
                idx += 1
                guard idx < args.count, !args[idx].isEmpty else {
                    throw CLIError.invalidArgument("--migrate-agent requires a LaunchAgent label")
                }
                migrateLabels.append(args[idx])
            default:
                throw CLIError.invalidArgument("Unknown option for install: \(args[idx])")
            }
            idx += 1
        }

        let config = try SnapClipConfig.load()
        let manager = SystemDefaultsManager()
        let binaryPath = resolveExecutablePath()
        let plistURL = manager.launchAgentPlistURL()

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for legacyLabel in migrateLabels {
            unloadLaunchAgent(label: legacyLabel)
            let legacyPlist = manager.launchAgentPlistURL(label: legacyLabel)
            if FileManager.default.fileExists(atPath: legacyPlist.path) {
                try? FileManager.default.removeItem(at: legacyPlist)
            }
        }

        let createdBackup = try manager.applyInstallDefaults(config: config)
        refreshSystemUIServer()
        let plistData = try manager.renderLaunchAgentPlist(binaryPath: binaryPath, config: config)
        try plistData.write(to: plistURL, options: .atomic)

        if !noLoad {
            unloadLaunchAgent(label: SystemDefaultsManager.launchAgentLabel)
            try bootstrapLaunchAgent(plistURL: plistURL)
        }

        print("Installed SnapClip (\(binaryPath))")
        print("  Staging:      \(config.stagingURL().path)")
        print("  Destination:  \(config.destinationURL().path)")
        print("  LaunchAgent:  \(plistURL.path)")
        if !migrateLabels.isEmpty {
            print("  Migrated:     \(migrateLabels.joined(separator: ", "))")
        }
        if createdBackup {
            print("  Backup saved: \(manager.backupFileURL(config: config).path)")
        }
        if noLoad {
            print("  Skipped launchctl bootstrap (--no-load).")
        } else {
            print("  Service status: loaded and running.")
        }
    }

    private static func runUninstall() throws {
        let config = try SnapClipConfig.load()
        let manager = SystemDefaultsManager()
        let plistURL = manager.launchAgentPlistURL()

        unloadLaunchAgent(label: SystemDefaultsManager.launchAgentLabel)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
        let restored = try manager.restoreDefaultsFromBackup(config: config)
        refreshSystemUIServer()

        print("Uninstalled SnapClip LaunchAgent.")
        print(restored
            ? "  Restored original com.apple.screencapture preferences."
            : "  No defaults backup found; existing com.apple.screencapture preferences left untouched.")
    }

    private static func runStatus(args: [String]) throws {
        let report = try collectReport(conflictLabel: nil)
        if args.contains("--json") {
            try printJSON(report)
            return
        }
        print("SnapClip \(SnapClipVersion.current)")
        print("  Status:       \(report.healthy ? "healthy" : "attention needed")")
        print("  LaunchAgent:  \(report.launchAgentLabel) (\(report.launchAgentLoaded ? "loaded" : "not loaded"))")
        print("  Staging:      \(report.stagingPath) (\(report.stuckFilesInStaging) pending)")
        print("  Destination:  \(report.destinationPath)")
    }

    private static func runDoctor(args: [String]) throws {
        var jsonOutput = false
        var conflictLabel: String?
        var idx = 0
        while idx < args.count {
            switch args[idx] {
            case "--json":
                jsonOutput = true
            case "--conflict-agent":
                idx += 1
                guard idx < args.count, !args[idx].isEmpty else {
                    throw CLIError.invalidArgument("--conflict-agent requires a LaunchAgent label")
                }
                conflictLabel = args[idx]
            default:
                throw CLIError.invalidArgument("Unknown option for doctor: \(args[idx])")
            }
            idx += 1
        }

        let report = try collectReport(conflictLabel: conflictLabel)
        if jsonOutput {
            try printJSON(report)
        } else {
            print("SnapClip Doctor (\(report.healthy ? "PASS" : "ISSUES FOUND"))")
            for check in report.checks {
                let badge = check.ok ? "[OK]" : "[FAIL]"
                print("  \(badge) \(check.name): \(check.detail)")
            }
        }
        if !report.healthy {
            exit(1)
        }
    }

    private static func runConfig(args: [String]) throws {
        let sub = args.first ?? "show"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = SnapClipConfig.expandPath(SnapClipConfig.defaultConfigPath, homeDirectory: home)

        switch sub {
        case "path":
            print(path)
        case "init":
            if FileManager.default.fileExists(atPath: path) {
                print("Config already exists at \(path)")
            } else {
                try SnapClipConfig().save(to: path, homeDirectory: home)
                print("Created default config at \(path)")
            }
        case "show":
            let config = try SnapClipConfig.load(from: path, homeDirectory: home)
            try printJSON(config)
        default:
            throw CLIError.invalidArgument("Unknown config action '\(sub)' (expected: show | init | path)")
        }
    }

    private static func runDonate(args: [String]) throws {
        var jsonOutput = false
        var openBrowser = false
        var channel: String?

        for arg in args {
            switch arg {
            case "--json":
                jsonOutput = true
            case "--open":
                openBrowser = true
            default:
                if arg.hasPrefix("-") {
                    throw CLIError.invalidArgument("Unknown option for donate: \(arg)")
                }
                if arg.lowercased() == "open", channel == nil, !openBrowser {
                    openBrowser = true
                } else if channel == nil {
                    channel = arg
                } else {
                    throw CLIError.invalidArgument("Usage: snapclip donate [github] [--open] [--json]")
                }
            }
        }

        let validated = try SnapClipSupport.buildReport(channel: channel, opened: false)
        if openBrowser {
            guard let url = URL(string: validated.url), NSWorkspace.shared.open(url) else {
                throw CLIError.openBrowserFailed(validated.url)
            }
        }

        let report = try SnapClipSupport.buildReport(channel: channel, opened: openBrowser)
        if jsonOutput {
            try printJSON(report)
            return
        }

        print("Support SnapClip")
        print("  GitHub Sponsors:  \(report.githubSponsors)")
        if report.opened {
            print("\nOpened GitHub Sponsors in your browser.")
        } else {
            print("\nRun 'snapclip donate --open' to open in your browser.")
        }
    }

    private static func collectReport(conflictLabel: String?) throws -> DoctorReport {
        let config = try SnapClipConfig.load()
        let manager = SystemDefaultsManager()
        let conflictLoaded = conflictLabel.map { isLaunchAgentLoaded(label: $0) } ?? false
        return manager.buildDoctorReport(
            config: config,
            binaryPath: resolveExecutablePath(),
            launchAgentLoaded: isLaunchAgentLoaded(label: SystemDefaultsManager.launchAgentLabel),
            conflictingAgentLabel: conflictLabel,
            conflictingAgentLoaded: conflictLoaded
        )
    }

    private static func resolveExecutablePath() -> String {
        SystemDefaultsManager.resolveLaunchAgentExecutablePath(
            argumentZero: CommandLine.arguments[0],
            environmentPATH: ProcessInfo.processInfo.environment["PATH"],
            fallbackMachOPath: queryMachOExecutablePath()
        )
    }

    private static func queryMachOExecutablePath() -> String? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func launchdDomain() -> String {
        "gui/\(getuid())"
    }

    private static func isLaunchAgentLoaded(label: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["print", "\(launchdDomain())/\(label)"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func unloadLaunchAgent(label: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "\(launchdDomain())/\(label)"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func bootstrapLaunchAgent(plistURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootstrap", launchdDomain(), plistURL.path]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CLIError.launchdFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func refreshSystemUIServer() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["SystemUIServer"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printUsage() {
        print("""
        SnapClip \(SnapClipVersion.current): macOS screenshot to clipboard, disk, and floating preview

        Usage:
          snapclip <command> [options]

        Commands:
          run [--config <path>] [--clipboard-only] [--no-preview]
              Run the watcher daemon (invoked by LaunchAgent)
          install [--no-load] [--migrate-agent <label>]
              Back up macOS screencapture defaults, configure staging, and install LaunchAgent
          uninstall
              Unload LaunchAgent and restore backed-up screencapture defaults
          status [--json]
              Show daemon and staging summary
          doctor [--json] [--conflict-agent <label>]
              Run diagnostics and exit non-zero on issues
          config [show|init|path]
              Inspect or initialize ~/.config/snapclip/config.json
          donate [github] [--open] [--json]
              Show or open the GitHub Sponsors support link
          version
              Print version
        """)
    }
}

private enum CLIError: LocalizedError {
    case invalidArgument(String)
    case launchdFailed(String)
    case openBrowserFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let msg): return msg
        case .launchdFailed(let msg): return "launchctl bootstrap failed: \(msg)"
        case .openBrowserFailed(let url): return "Could not open browser for \(url)"
        }
    }
}
