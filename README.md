<div align="center">

# SnapClip

### Copy macOS screenshots to the clipboard, Desktop, and a floating preview at the same time

[![Release](https://img.shields.io/github/v/release/aklkbqx/snapclip?color=FF891A&label=Release&style=flat-square)](https://github.com/aklkbqx/snapclip/releases)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-EA4AAA?style=flat-square&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/aklkbqx)
[![License: MIT](https://img.shields.io/badge/License-MIT-34C759.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-blue?style=flat-square&logo=apple&logoColor=white)](https://github.com/aklkbqx/snapclip/releases)
[![Arch](https://img.shields.io/badge/Arch-arm64%20%7C%20x86__64-orange?style=flat-square)](https://github.com/aklkbqx/snapclip/releases)

<br/>

<a href="#how-it-works">
  <img src="docs/assets/showcase.gif" alt="SnapClip capturing a screenshot, saving to Desktop, pasting via Cmd+V, and showing the hoverable corner preview card" width="800" />
</a>

<p>
  <a href="#why-it-exists">Why it exists</a> ·
  <a href="#install">Install</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#preview-controls">Preview controls</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#support">Support</a>
</p>

</div>

Requires no Screen Recording or Accessibility permissions. `snapclip` runs as a background user agent that watches the staging folder where macOS `screencapture` already writes image files.

```text
  Cmd+Shift+3 / 4 --> ~/.local/state/snapclip/staging --+--> clipboard (PNG + TIFF)
                                                        +--> ~/Desktop/Screenshot ...png
                                                        +--> corner preview on cursor display
```

## Why it exists

macOS `screencapture` forces a trade-off between speed and keeping files:

- Setting `target` to `clipboard` skips writing the screenshot file.
- Keeping the native macOS thumbnail enabled delays writing the file for ~5 seconds until the thumbnail dismisses.

`snapclip install` backs up your current `com.apple.screencapture` defaults, disables the 5-second thumbnail delay (`show-thumbnail = 0`), points screenshots to a staging folder, and starts the watcher. `snapclip uninstall` stops the agent and restores your original `screencapture` preferences.

## Install

Requires macOS 14 or newer.

### Homebrew

```sh
brew install aklkbqx/snapclip/snapclip
snapclip install
snapclip doctor
```

### Release archive

Download `snapclip_<version>_darwin_universal.tar.gz` and `SHA256SUMS` from [Releases](https://github.com/aklkbqx/snapclip/releases/latest), verify the checksum, and install the binary onto your `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf snapclip_*_darwin_universal.tar.gz
install -m 755 snapclip ~/.local/bin/snapclip
snapclip install
```

### Build from source

Requires Swift 6.0+ (no external Swift packages):

```sh
git clone https://github.com/aklkbqx/snapclip.git
cd snapclip
make verify
make install
```

Add `~/.local/bin` to your `PATH` if needed, then configure the LaunchAgent and staging preferences:

```sh
snapclip install
snapclip doctor
```

To restore everything back to stock macOS behavior:

```sh
snapclip uninstall
```

## Commands

| Command | What it does |
| --- | --- |
| `snapclip run [--config <path>] [--clipboard-only] [--no-preview]` | Run the foreground watcher (used by `launchd`) |
| `snapclip install [--no-load] [--migrate-agent <label>]` | Back up defaults, apply staging config, and load `LaunchAgent` |
| `snapclip uninstall` | Unload `LaunchAgent` and restore backed-up `screencapture` settings |
| `snapclip status [--json]` | Print daemon status, staging queue count, and destination path |
| `snapclip doctor [--json] [--conflict-agent <label>]` | Verify binary, folders, defaults keys, and agent state |
| `snapclip config [show\|init\|path]` | Print active config, write defaults, or print config file path |
| `snapclip donate [github] [--open] [--json]` | Print the GitHub Sponsors URL, or open it in your browser |
| `snapclip version` | Print version |

<p align="center">
  <img src="docs/assets/cli.gif" alt="snapclip version, config show, and donate in a terminal" width="750" />
</p>

## Preview controls

The floating card appears in the bottom-right corner of the monitor holding the mouse cursor and stays out of focus so typing is never interrupted.

- **Click**: open the saved file in Preview (in `--clipboard-only` mode where no file is kept, clicking dismisses).
- **Drag left or up**: drop the screenshot into another app, Finder, or terminal.
- **Hover top-right buttons**: move to macOS Trash (`trash`) or close (`xmark`).
- **Swipe right or right-click**: dismiss the preview without touching the saved file.

## Configuration

Create `~/.config/snapclip/config.json`:

```sh
snapclip config init
```

Default values:

```json
{
  "destinationDirectory": "~/Desktop",
  "includeTiffOnPasteboard": true,
  "keepFile": true,
  "logPath": "~/Library/Logs/snapclip.log",
  "maxLogSizeBytes": 1048576,
  "previewAutoDismissSeconds": 4.5,
  "previewHoverDismissSeconds": 2.5,
  "showFloatingPreview": true,
  "stagingDirectory": "~/.local/state/snapclip/staging",
  "stateDirectory": "~/.local/state/snapclip",
  "watchScreenRecordings": true
}
```

## How it works

`SnapClipCore` monitors the staging directory using kernel vnode events (`O_EVTONLY`), sorts pending captures oldest-first, processes them serially to preserve clipboard order, waits asynchronously for image trailers and stable byte counts via `ImageIO`, writes PNG plus LZW-compressed TIFF onto a single `NSPasteboardItem`, and moves the file cleanly into `destinationDirectory`.

New behaviors can attach to the pipeline through `CapturePostProcessor` and `CaptureActionSink` without modifying the directory watcher.

## Packaging

Build a universal macOS (`arm64` + `x86_64`) release tarball, `SHA256SUMS`, and Homebrew formula under `dist/packages/`:

```sh
make package
```

## Security and privacy

SnapClip opens no network sockets, makes no outbound HTTP requests during capture watching, and collects no telemetry. See [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and our [Code of Conduct](CODE_OF_CONDUCT.md).

## Support

SnapClip is free and open-source software under the MIT License. If it saves you time capturing and sharing screenshots, you can support ongoing development via [GitHub Sponsors](https://github.com/sponsors/aklkbqx):

```sh
# Print the GitHub Sponsors URL
snapclip donate

# Open GitHub Sponsors in your browser
snapclip donate --open
```

## License

Distributed under the MIT License. See [LICENSE](LICENSE).
