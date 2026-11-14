import Darwin
import Foundation

/// Advisory non-blocking file lock preventing multiple `snapclip run` instances on the same state directory.
public final class ProcessFileLock {
    private var fd: Int32 = -1
    public let lockURL: URL

    public init(stateDirectory: URL) {
        self.lockURL = stateDirectory.appendingPathComponent("snapclip.lock")
    }

    deinit {
        release()
    }

    /// Attempts to acquire an exclusive lock, writing the current PID on success.
    public func acquire() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let opened = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard opened >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Unable to open daemon lock file \(lockURL.path)"]
            )
        }

        if flock(opened, LOCK_EX | LOCK_NB) != 0 {
            let err = errno
            close(opened)
            if err == EWOULDBLOCK || err == EAGAIN {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(err),
                    userInfo: [NSLocalizedDescriptionKey: "Another snapclip daemon is already running (\(lockURL.path))"]
                )
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "Unable to lock daemon file \(lockURL.path)"]
            )
        }

        ftruncate(opened, 0)
        let pidLine = "\(getpid())\n"
        _ = pidLine.withCString { ptr in
            Darwin.write(opened, ptr, strlen(ptr))
        }
        self.fd = opened
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
