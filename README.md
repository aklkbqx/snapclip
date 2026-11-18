<div align="center">

# SnapClip

**Every macOS screenshot goes to your clipboard and your Desktop right away.**

[![Release](https://img.shields.io/github/v/release/aklkbqx/snapclip?color=FF891A&label=Release&style=flat-square)](https://github.com/aklkbqx/snapclip/releases)
[![Homebrew](https://img.shields.io/badge/Homebrew-aklkbqx%2Fsnapclip-FBB040?style=flat-square&logo=homebrew&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/License-MIT-34C759.svg?style=flat-square)](LICENSE)

<img src="docs/assets/showcase.gif" alt="SnapClip copying a Cmd+Shift+4 screenshot to the clipboard, saving the PNG to Desktop immediately, pasting it with Cmd+V, and showing a corner preview card with Trash and Close buttons" width="800" />

</div>

## What it does

With stock macOS, `Cmd+Shift+4` saves a file but does not copy it, and the file waits about 5 seconds for the corner thumbnail to go away. `Cmd+Ctrl+Shift+4` copies but saves no file. SnapClip gives you both:

- **Copied at once.** Press `Cmd+Shift+3`, `4`, or `5`, then paste with `Cmd+V`.
- **Saved at once.** The file lands on your Desktop with no 5-second wait.
- **No permissions.** macOS still takes the screenshot, so SnapClip needs no Screen Recording or Accessibility access.

A small preview card shows up in the corner without taking focus. Drag it into another app, click to open it in Preview, or hover for Trash and Close.

## Install

macOS 14 or newer, Apple silicon or Intel.

```sh
brew install aklkbqx/snapclip/snapclip
snapclip install
```

That is all. Take a screenshot to try it. `snapclip doctor` checks the setup if something looks off.

Other ways to install (release archive, build from source): [docs/install.md](docs/install.md).

To undo everything and restore your original screenshot settings:

```sh
snapclip uninstall
```

## Settings

The two most common changes go in `~/.config/snapclip/config.json`:

```json
{
  "destinationDirectory": "~/Pictures/Screenshots",
  "keepFile": true
}
```

- `destinationDirectory`: where screenshots are saved (default `~/Desktop`).
- `keepFile`: set to `false` to copy to the clipboard only and keep no file.

All options and commands: [docs/reference.md](docs/reference.md).

## FAQ

**How does it work without Screen Recording permission?**
SnapClip does not record the screen or watch the keyboard. `snapclip install` points macOS's own screenshots at a private folder, and SnapClip copies and moves each finished file from there. Details: [docs/how-it-works.md](docs/how-it-works.md).

**Does it work with screen recordings and non-English macOS?**
Yes. Finished `Cmd+Shift+5` recordings move to the same folder with their own corner preview card (the clipboard is left alone), and files are matched by type, not by an English name.

**Does it send anything over the network?**
No. No network connections and no telemetry. See [SECURITY.md](SECURITY.md).

## More

[How it works](docs/how-it-works.md) ·
[Contributing](CONTRIBUTING.md) ·
[Security](SECURITY.md) ·
[Sponsor](https://github.com/sponsors/aklkbqx) ·
[MIT License](LICENSE)
