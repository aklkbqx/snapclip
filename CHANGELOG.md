# Changelog

## 0.2.0 (2026-11-18)

- Route `Cmd+Shift+5` screen recordings (`location-screenrecording`) through staging when `watchScreenRecordings` is enabled so recordings appear in the corner preview card instead of finishing silently when macOS `show-thumbnail` is disabled.
- Check recording completion via `AVFoundation` (`isPlayable` + size stability) so long or paused recordings are never quarantined mid-recording and never block concurrent screenshots.
- Show first-frame corner preview thumbnails with a `Saved` duration badge and play indicator for finished `.mov` / `.mp4` recordings (click to open, drag to share, or move to Trash) while leaving the clipboard untouched.
- Add `screencapture_recording_location` checks to `snapclip doctor` and expanded startup drift warnings in `CaptureWatcher`.

## 0.1.0 (2026-11-14)

- Initial modular Swift Package (`SnapClipCore`, `SnapClipUI`, `SnapClipCLI`) targeting macOS 14+ with zero third-party dependencies.
- Serial staging watcher (`O_EVTONLY`), async stability reader (`StabilityReader`), bounded quarantine retries for unreadable files, and atomic PNG + LZW-compressed TIFF clipboard copy.
- Mouse-screen AppKit preview card (`FloatingThumbnailController`, `ThumbnailPreviewView`) with `1x`-aligned drawing, drag-out, swipe/right-click dismiss, and macOS Trash action.
- Reversible CLI lifecycle (`run`, `install`, `uninstall`, `status`, `doctor`, `config`, `donate`, `version`) with `ProcessFileLock` and clean `SIGINT`/`SIGTERM` shutdown.
- Local verification (`scripts/verify.sh`), universal (`arm64` + `x86_64`) tarball + `SHA256SUMS` packaging (`scripts/package.sh`), and Homebrew tap helper (`scripts/update-homebrew-tap.sh`).
