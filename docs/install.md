# Installing SnapClip

SnapClip needs macOS 14 (Sonoma) or newer, on Apple silicon (`arm64`) or Intel (`x86_64`).

Whichever way you install it, finish with:

```sh
snapclip install   # back up screenshot settings, start the background agent
snapclip doctor    # check that everything is in place
```

## Homebrew (recommended)

```sh
brew install aklkbqx/snapclip/snapclip
```

To upgrade an existing installation and refresh `com.apple.screencapture` defaults (such as routing screen recordings after `0.1.0`) while keeping your backup intact:

```sh
brew upgrade snapclip
snapclip install
```

## Release archive

Download `snapclip_<version>_darwin_universal.tar.gz` and `SHA256SUMS` from [GitHub Releases](https://github.com/aklkbqx/snapclip/releases/latest), check the archive, and put `snapclip` on your `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf snapclip_*_darwin_universal.tar.gz
install -m 755 snapclip ~/.local/bin/snapclip
```

## Build from source

Requires Swift 6.0 or newer. There are no external Swift package dependencies.

```sh
git clone https://github.com/aklkbqx/snapclip.git
cd snapclip
make verify
make install
```

Add `~/.local/bin` to your `PATH` if it is not there yet.

## Uninstall

```sh
snapclip uninstall
```

This stops the background agent (`com.snapclip.agent`), deletes its `LaunchAgent` plist, and restores your original `com.apple.screencapture` settings from `~/.local/state/snapclip/backup-defaults.json`. Then remove the binary (`brew uninstall snapclip`, or delete `~/.local/bin/snapclip`).
