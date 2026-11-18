# SnapClip Agent Instructions

These instructions apply to the `snapclip` repository (`/Volumes/SSD_ROOT/Documents/work-code/projects/snapclip`), including coordinating CLI/daemon releases with the nested `site/` repository (`https://snapclip.aklkbqx.com`).

## Core Architecture & Hygiene

- Zero third-party Swift dependencies (`Package.swift` uses Swift 6.0 / macOS 14+ system frameworks only).
- Keep all `com.apple.screencapture` and `launchd` modifications reversible (`SystemDefaultsManager` preserves the first `backup-defaults.json`).
- Keep root repo files free of hardcoded home directory prefixes and private handles (`scripts/verify.sh` enforces hygiene checks on `.md`, `.swift`, `.sh`).
- Never create `.github/`, GitHub Actions workflows, or third-party cloud hosting configs.

## Release & Deploy Rule (CLI + Homebrew + Site + Macs)

Whenever a user-facing behavior, `SnapClipConfig` key, CLI flag, or `snapclip doctor` check changes, or when asked to release / push / deploy:

1. **Code, Docs & Version Sync:**
   - Bump `SnapClipVersion.current` in `Sources/SnapClipCLI/SnapClipCLI.swift` and add an entry to `CHANGELOG.md`.
   - Keep `README.md`, `docs/how-it-works.md`, `docs/reference.md`, and `docs/install.md` accurate.
   - Add/update tests in `Tests/SnapClipCoreTests/` without mutating `NSPasteboard.general` or `~/Desktop`.

2. **Verify & Package:**
   - Run `make verify` (must pass `swift test`, release build, CLI smoke checks, hygiene checks, and `git diff --check`).
   - Run `make package` to build the universal (`arm64` + `x86_64`) archive, `SHA256SUMS`, and `dist/packages/<version>/snapclip.rb`.

3. **GitHub Release & Homebrew Tap:**
   - Verify git identity matches `aklkbqx <135732879+aklkbqx@users.noreply.github.com>` with zero AI attribution in commits.
   - Commit cleanly on `main`, create annotated tag `v<version>`, push `main` and tag to `origin`.
   - Publish the GitHub release via `gh release create v<version>` with `snapclip_<version>_darwin_universal.tar.gz` and `SHA256SUMS`.
   - Run `make publish-homebrew-tap` to update and push `Formula/snapclip.rb` in `aklkbqx/homebrew-snapclip`.

4. **Site Sync & Deploy (`site/`):**
   - Never treat a CLI/Homebrew release as finished without updating `site/` (`https://snapclip.aklkbqx.com`). Follow `site/AGENTS.md`:
     - Sync `site/package.json`, `site/src/data/outputs.js` (`DOCTOR_CHECKS`, `DOCTOR_FAIL_DETAIL`, `CONFIG_FIELDS`), `site/src/content/en.js`, and `site/src/content/th.js` whenever version, `doctor`, or config fields change.
     - Run `cd site && bun run build && bun run test` so `prepare:site-data` updates `src/data/release.json` from the published GitHub release and `check:static` passes cleanly.
     - Commit changes inside `site/` locally (do not create or push a remote git repo for `site/` without owner consent).
     - Build `linux/amd64` with the pinned base image in `site/data/runtime-image.json` and push **both `:latest` and `:<version>`** to `ghcr.io/aklkbqx/snapclip-site`, then pull and recreate the Watchtower-enabled container on `ssh private` under `/root/apps/<owner-email>/aklkbqx.com/snapclip` and verify `https://snapclip.aklkbqx.com/` and `/th/` return HTTP 200 with the new release facts.

5. **Machine Rollout:**
   - Upgrade via Homebrew and run `snapclip install` + `snapclip doctor` on the local Mac and `ssh macbook` (when online; pass `--migrate-agent <legacy-label>` if replacing an older agent).
