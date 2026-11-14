# Changelog

## 0.1.0 (2026-11-14)

- Initial modular Swift Package (`SnapClipCore`, `SnapClipUI`, `SnapClipCLI`) targeting macOS 14+ with zero third-party dependencies.
- Serial staging watcher (`O_EVTONLY`), async stability reader (`StabilityReader`), bounded quarantine retries for unreadable files, and atomic PNG + LZW-compressed TIFF clipboard copy.
- Mouse-screen AppKit preview card (`FloatingThumbnailController`, `ThumbnailPreviewView`) with `1x`-aligned drawing, drag-out, swipe/right-click dismiss, and macOS Trash action.
- Reversible CLI lifecycle (`run`, `install`, `uninstall`, `status`, `doctor`, `config`, `donate`, `version`) with `ProcessFileLock` and clean `SIGINT`/`SIGTERM` shutdown.
- Local verification (`scripts/verify.sh`), universal (`arm64` + `x86_64`) tarball + `SHA256SUMS` packaging (`scripts/package.sh`), and Homebrew tap helper (`scripts/update-homebrew-tap.sh`).
