# Contributing

SnapClip is a small macOS CLI and background watcher with zero third-party Swift dependencies. Keep changes focused on reliable `screencapture` watching, pasteboard accuracy, AppKit preview behavior, and reversible setup. Contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Before opening a pull request, run:

```sh
make verify
```

Notes:

- Add tests in `Tests/SnapClipCoreTests/` for behavior changes without mutating `NSPasteboard.general` or personal `~/Desktop` folders.
- Keep `screencapture` and `launchd` modifications reversible in `SystemDefaultsManager`.
- No GitHub Actions or cloud CI workflows are used; verify changes locally on macOS and note tested OS version and display scale in your PR.

## Building from source

Requires Swift 6.0 or newer:

```sh
make verify    # build and run the tests
make install   # install to ~/.local/bin/snapclip
```

## Packaging a release

Build a universal (`arm64` + `x86_64`) archive, `SHA256SUMS`, and the Homebrew formula under `dist/packages/`:

```sh
make package
```

See [docs/how-it-works.md](docs/how-it-works.md) for the pipeline.
