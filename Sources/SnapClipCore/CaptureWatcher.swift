import Foundation

/// Watches the staging directory via kernel vnode events (`O_EVTONLY`) and processes captures serially in chronological order.
public final class CaptureWatcher: @unchecked Sendable {
    private let config: SnapClipConfig
    private let homeDirectory: String
    private let pipeline: SnapClipPipeline
    private let stabilityReader: StabilityReader
    private let destinationStore: DestinationStore
    private let defaultsStore: any DefaultsStoring
    private let logger: any SnapClipLogging
    private let maxFailureCycles: Int
    private let stateQueue = DispatchQueue(label: "com.snapclip.watcher", qos: .userInitiated)

    private var stagingFD: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var rescanTimer: DispatchSourceTimer?
    private var isProcessing = false
    private var pendingRescan = false
    private var isStopped = false
    private var failureCounts: [String: Int] = [:]
    private var copiedDigests = BoundedKeyValueCache<String, String>(capacity: 128)

    public init(
        config: SnapClipConfig,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        pipeline: SnapClipPipeline,
        stabilityReader: StabilityReader = StabilityReader(),
        destinationStore: DestinationStore = DestinationStore(),
        defaultsStore: any DefaultsStoring = SuiteDefaultsStore(),
        logger: any SnapClipLogging = StandardLogger(),
        maxFailureCycles: Int = 3
    ) {
        self.config = config
        self.homeDirectory = homeDirectory
        self.pipeline = pipeline
        self.stabilityReader = stabilityReader
        self.destinationStore = destinationStore
        self.defaultsStore = defaultsStore
        self.logger = logger
        self.maxFailureCycles = max(1, maxFailureCycles)
    }

    /// Rotates oversized log files, verifies preference alignment, attaches the directory watcher, and scans staging.
    public func start() throws {
        var alreadyRunning = false
        stateQueue.sync {
            alreadyRunning = directorySource != nil && !isStopped
        }
        guard !alreadyRunning else { return }

        let stagingDir = config.stagingURL(homeDirectory: homeDirectory)
        let destinationDir = config.destinationURL(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        if config.keepFile {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        rotateLogIfNeeded()
        logConfigurationWarnings(expectedStagingPath: stagingDir.path)

        let fd = open(stagingDir.path, O_EVTONLY)
        guard fd >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Unable to open staging directory for watching: \(stagingDir.path)"]
            )
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: stateQueue
        )
        source.setEventHandler { [weak self] in
            self?.scanStagingOnStateQueue()
        }
        source.setCancelHandler {
            close(fd)
        }

        stateQueue.sync {
            self.isStopped = false
            self.stagingFD = fd
            self.directorySource = source
        }
        source.resume()

        logger.log("started watching \(stagingDir.path) (keepFile=\(config.keepFile), preview=\(config.showFloatingPreview))")
        stateQueue.async { [weak self] in
            self?.scanStagingOnStateQueue()
        }
    }

    public func stop() {
        stateQueue.sync {
            isStopped = true
            pendingRescan = false
            rescanTimer?.cancel()
            rescanTimer = nil
            directorySource?.cancel()
            directorySource = nil
            stagingFD = -1
        }
    }

    /// Schedules an immediate scan pass on the watcher queue.
    public func triggerScan() {
        stateQueue.async { [weak self] in
            self?.scanStagingOnStateQueue()
        }
    }

    private func scanStagingOnStateQueue() {
        guard !isStopped else { return }
        if isProcessing {
            pendingRescan = true
            return
        }

        let stagingDir = config.stagingURL(homeDirectory: homeDirectory)
        let destinationDir = config.destinationURL(homeDirectory: homeDirectory)
        let candidates = destinationStore.sortedMediaURLs(
            in: stagingDir,
            includeVideos: config.watchScreenRecordings
        )
        guard !candidates.isEmpty else { return }

        isProcessing = true
        pendingRescan = false

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var hadIncomplete = false

            for url in candidates {
                if self.checkStopped() { break }
                let incomplete = await self.processCandidateSerially(url: url, destinationDir: destinationDir)
                if incomplete {
                    hadIncomplete = true
                }
            }

            self.finishBatchOnStateQueue(hadIncomplete: hadIncomplete)
        }
    }

    private func checkStopped() -> Bool {
        stateQueue.sync { isStopped }
    }

    private func finishBatchOnStateQueue(hadIncomplete: Bool) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isProcessing = false
            guard !self.isStopped else { return }

            if self.pendingRescan {
                self.pendingRescan = false
                self.scanStagingOnStateQueue()
                return
            }

            if hadIncomplete {
                self.scheduleFallbackRescanOnStateQueue()
            }
        }
    }

    /// Returns `true` when a still-existing candidate failed stability checks and remains queued for retry.
    private func processCandidateSerially(url: URL, destinationDir: URL) async -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if SupportedMedia.isVideo(extension: ext) {
            let (readiness, artifact) = await stabilityReader.readCompleteVideo(at: url)
            switch readiness {
            case .inProgress:
                // Recording is still active or flushing; retry without counting toward quarantine.
                return true
            case .incomplete:
                return handleIncompleteCandidate(url: url)
            case .ready:
                clearFailureCount(for: url.path)
                if let artifact {
                    _ = await pipeline.runVideoPipeline(artifact, destinationDirectory: destinationDir)
                }
                return false
            }
        }

        guard let artifact = await stabilityReader.readCompleteImage(at: url) else {
            return handleIncompleteCandidate(url: url)
        }

        clearFailureCount(for: url.path)
        let previousDigest: String? = stateQueue.sync { copiedDigests[name] }
        let outcome = await pipeline.runImagePipeline(
            artifact,
            alreadyCopiedDigest: previousDigest,
            destinationDirectory: destinationDir
        )
        stateQueue.sync {
            copiedDigests[name] = outcome.digest
        }
        return false
    }

    private func clearFailureCount(for path: String) {
        stateQueue.sync {
            _ = failureCounts.removeValue(forKey: path)
        }
    }

    private func handleIncompleteCandidate(url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            clearFailureCount(for: url.path)
            return false
        }

        let count: Int = stateQueue.sync {
            let next = (failureCounts[url.path] ?? 0) + 1
            failureCounts[url.path] = next
            return next
        }

        if count >= maxFailureCycles {
            quarantineUnreadableFile(at: url)
            clearFailureCount(for: url.path)
            return false
        }

        logger.log("deferring incomplete capture for retry (\(count)/\(maxFailureCycles)): \(url.lastPathComponent)")
        return true
    }

    private func quarantineUnreadableFile(at url: URL) {
        let failedDir = config.stateURL(homeDirectory: homeDirectory).appendingPathComponent("failed", isDirectory: true)
        do {
            let quarantined = try destinationStore.moveToDestination(from: url, toDirectory: failedDir)
            logger.log("quarantined unreadable staging file to \(quarantined.path)")
        } catch {
            logger.log("failed to quarantine unreadable file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func scheduleFallbackRescanOnStateQueue() {
        guard !isStopped, rescanTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.rescanTimer?.cancel()
            self?.rescanTimer = nil
            self?.scanStagingOnStateQueue()
        }
        rescanTimer = timer
        timer.resume()
    }

    private func rotateLogIfNeeded() {
        let logURL = config.resolvedLogURL(homeDirectory: homeDirectory)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > config.maxLogSizeBytes else {
            return
        }
        let rotatedURL = logURL.appendingPathExtension("1")
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: logURL, to: rotatedURL)
    }

    private func logConfigurationWarnings(expectedStagingPath: String) {
        let currentScreenshotLocation = defaultsStore.string(forKey: "location-screenshot") ?? defaultsStore.string(forKey: "location")
        if let currentScreenshotLocation, currentScreenshotLocation != expectedStagingPath {
            logger.log("warning: com.apple.screencapture location-screenshot points to '\(currentScreenshotLocation)' instead of '\(expectedStagingPath)'; run 'snapclip install' to re-sync")
        }

        if config.watchScreenRecordings {
            let currentRecordingLocation = defaultsStore.string(forKey: "location-screenrecording") ?? currentScreenshotLocation
            if let currentRecordingLocation, currentRecordingLocation != expectedStagingPath {
                logger.log("warning: com.apple.screencapture location-screenrecording points to '\(currentRecordingLocation)' instead of '\(expectedStagingPath)'; run 'snapclip install' to route Cmd+Shift+5 recordings through SnapClip")
            }
        }

        if defaultsStore.object(forKey: "show-thumbnail") != nil && defaultsStore.bool(forKey: "show-thumbnail") {
            logger.log("warning: com.apple.screencapture show-thumbnail is enabled; run 'snapclip install' to restore instant flush and floating preview")
        }

        let screenshotTarget = defaultsStore.string(forKey: "target-screenshot") ?? defaultsStore.string(forKey: "target") ?? "file"
        if screenshotTarget != "file" {
            logger.log("warning: com.apple.screencapture target-screenshot is '\(screenshotTarget)' instead of 'file'; run 'snapclip install' to restore file + preview capture")
        }
    }
}
