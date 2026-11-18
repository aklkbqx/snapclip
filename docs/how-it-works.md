# How SnapClip works

```text
  Cmd+Shift+3 / 4 / 5 --> ~/.local/state/snapclip/staging --+--> clipboard (PNG + TIFF)
                                                            +--> ~/Desktop/Screenshot ...png
                                                            +--> corner preview on cursor display
```

SnapClip does not capture your screen or listen to the keyboard. macOS's own `screencapture` still takes every screenshot. That is why SnapClip needs no Screen Recording or Accessibility permission.

## What `snapclip install` changes

- Backs up your current `com.apple.screencapture` settings to `~/.local/state/snapclip/backup-defaults.json`.
- Sets `show-thumbnail = 0`. With the stock thumbnail on, macOS holds the file back until the thumbnail goes away (about 5 seconds). With it off, the file is written right away and SnapClip shows its own preview card for both screenshots and finished screen recordings.
- Points screenshots (and screen recordings when `watchScreenRecordings` is enabled) at a staging folder (`~/.local/state/snapclip/staging`).
- Loads a `LaunchAgent` (`com.snapclip.agent`) that runs `snapclip run`.

`snapclip uninstall` reverses all of this.

## The pipeline

`SnapClipCore` watches the staging folder with kernel vnode notifications (`O_EVTONLY`). For each new file it:

1. Sorts pending captures oldest-first, so quick bursts keep their order.
2. Waits until the media is complete: images check format trailers, byte stability, and `ImageIO` pixel dimensions; screen recordings wait without blocking screenshots until `AVFoundation` reports a finalized playable asset and size stops changing.
3. For screenshots, writes PNG plus LZW-compressed TIFF onto a single `NSPasteboardItem`. (Screen recordings leave the clipboard untouched.)
4. Moves the file into `destinationDirectory` (adding a number if the name is taken) and displays the bottom-right corner preview card.

Files are matched by extension (`png`, `jpg`, `jpeg`, `heic`, `tiff`, `tif`, `webp`, plus `mov` / `mp4` when `watchScreenRecordings` is on), not by an English `Screenshot` prefix, so localized macOS file names work.

Custom workflows can hook in through the `CapturePostProcessor` and `CaptureActionSink` protocols without changing the watcher.
