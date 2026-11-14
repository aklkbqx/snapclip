# SnapClip SEO & Community Launch Plan

> [!IMPORTANT]
> Every post and directory listing below uses a direct developer voice audited against the project's anti-slop rules (no buzzwords, no fabricated claims, no em or en dashes). Attach `dist/media/showcase.mp4` on video platforms (Reddit, X) or `docs/assets/showcase.gif` on Markdown platforms (Dev.to, Zenn, GitHub).

## 1. GitHub Social Preview (OpenGraph Card)

GitHub's REST/GraphQL API does not expose an upload endpoint for custom OpenGraph images, so upload this once in the browser:

1. Open `https://github.com/aklkbqx/snapclip/settings`
2. Under **Social preview**, click **Edit** -> **Upload an image...**
3. Select `docs/assets/social-preview.png` (`1280x640`, < 500 KB)

Once set, links shared on Hacker News, Reddit, X, Discord, Slack, and LINE render the custom `1280x640` product card instead of a plain user avatar.

---

## 2. Staged Rollout Schedule

| Day | Channel | Recommended Window (ICT / UTC+7) | Focus |
| :--- | :--- | :--- | :--- |
| **Day 1** | Reddit `r/macapps` + `r/macos` | 20:00 to 22:00 (US East morning) | Lead with `dist/media/showcase.mp4` showing `Cmd+Shift+4` copying to clipboard, saving to Desktop, and revealing hover Trash/Close controls with zero permissions. |
| **Day 2** | Reddit `r/commandline` + `r/swift` + X / Bluesky | 20:00 to 22:00 (US East morning) | Focus on `O_EVTONLY` vnode watching, zero external Swift dependencies, reversible `com.apple.screencapture` backup, and `brew install`. |
| **Day 3** | PRs to curated Awesome Lists (high-authority backlinks) | Any time | Submit single-line PRs to `awesome-mac`, `open-source-mac-os-apps`, `awesome-swift`, and `awesome-macos-command-line`. |
| **Day 4** | Japanese (`Zenn.dev` / `Qiita`) + `DEV.to` walkthrough | 10:00 to 12:00 | Short technical post on why stock macOS delays screenshot files for 5 seconds (`show-thumbnail`) and how staging avoids Screen Recording TCC. |
| **Day 5** | Hacker News (`Show HN`) | 20:30 to 22:00 (Tue, Wed, or Thu) | Main launch once initial feedback and stars are on the repository. |

---

## 3. High-Authority Backlink PR Snippets (Awesome Lists)

Curated GitHub lists rank at the top of Google for `"open source macos screenshot tool"` and send steady organic traffic:

### `jaywcjlove/awesome-mac` (Screenshots section)
```markdown
* [SnapClip](https://github.com/aklkbqx/snapclip) - Copy macOS screenshots to the clipboard, Desktop, and a floating corner preview without Screen Recording permissions. ![Open-Source Software][OSS Icon]
```

### `serhii-londar/open-source-mac-os-apps` (Screenshots / Utilities section)
```markdown
- [SnapClip](https://github.com/aklkbqx/snapclip) - Lightweight Swift daemon and CLI that copies macOS `screencapture` shots to the clipboard and Desktop immediately without TCC permissions. `Swift`
```

### `matteocrippa/awesome-swift` (Tools / Utilities section)
```markdown
* [SnapClip](https://github.com/aklkbqx/snapclip) - Zero-dependency Swift 6 macOS utility that copies native screenshots to the clipboard, Desktop, and a non-blocking AppKit corner preview.
```

---

## 4. Ready-to-Post Community Copy

### 4.1 Reddit: `r/macapps` and `r/macos` (Upload `dist/media/showcase.mp4` as a Video post, paste body as first comment or description)

- **Title:** `I built SnapClip (free & open-source): Make Cmd+Shift+4 copy to clipboard AND save to Desktop immediately without Screen Recording permissions`
- **Body:**

```markdown
On stock macOS, taking screenshots always had two small annoyances for me:

1. `Cmd+Shift+4` saves a PNG to Desktop, skips the clipboard, and delays writing the file for ~5 seconds until the floating thumbnail disappears.
2. `Cmd+Ctrl+Shift+4` copies to the clipboard, skips saving the file, and gives you no corner thumbnail to drag into Finder, Slack, or a browser.

Most third-party screenshot tools replace the capture UI and ask for Screen Recording + Accessibility permissions. I wanted to keep the native macOS crosshair (`Cmd+Shift+3 / 4 / 5`) without granting screen permissions, so I wrote **SnapClip** in Swift (MIT license):

* **Zero TCC permissions:** macOS `screencapture` still takes the screenshot and writes it to a local staging folder (`~/.local/state/snapclip/staging`). SnapClip watches that folder with kernel `O_EVTONLY` events.
* **Clipboard + Desktop right away:** Disables the 5-second native thumbnail write delay (`show-thumbnail = 0`), writes PNG + TIFF onto your clipboard, and moves the file to `~/Desktop`.
* **Non-blocking corner preview:** Shows a small preview card on whichever monitor holds your cursor without stealing keyboard focus. Click to open in Preview, drag out to drop the file anywhere, swipe right to dismiss, or hover to click Trash / Close.
* **Clean uninstall:** `snapclip install` backs up your original `com.apple.screencapture` settings first, and `snapclip uninstall` puts everything back to stock macOS.

**Install via Homebrew (macOS 14+):**

```sh
brew install aklkbqx/snapclip/snapclip
snapclip install
snapclip doctor
```

GitHub (MIT, universal `arm64` + `x86_64`, zero external dependencies): https://github.com/aklkbqx/snapclip
```

---

### 4.2 Hacker News (`Show HN`)

- **Title:** `Show HN: SnapClip - Copy macOS screenshots to clipboard and Desktop with no permissions`
- **URL:** `https://github.com/aklkbqx/snapclip`
- **First Comment:**

```text
Hi HN, I built SnapClip to fix two stock macOS screencapture behaviors without replacing the built-in crosshair or granting Screen Recording permissions.

Out of the box, macOS makes you pick between saving files (`Cmd+Shift+4`, which also delays flushing the PNG to disk for ~5 seconds while the floating thumbnail stays on screen) or copying to the clipboard (`Cmd+Ctrl+Shift+4`, which writes no file and shows no drag-out preview).

SnapClip is a small zero-dependency Swift 6 CLI and LaunchAgent (~670 KB universal binary) that works alongside macOS `screencapture`:

- `snapclip install` backs up your current `com.apple.screencapture` preferences to JSON, sets `show-thumbnail = 0` so macOS flushes files right away, points screenshot output to `~/.local/state/snapclip/staging`, and loads a user LaunchAgent.
- The daemon watches the staging directory via `O_EVTONLY` vnode notifications, verifies image completion through `ImageIO` before reading, writes both PNG and LZW-compressed TIFF onto a single `NSPasteboardItem`, and moves the file to `~/Desktop` (or deletes the staged file in `--clipboard-only` mode).
- An AppKit `NSPanel` with `.nonactivatingPanel` presents a corner card on the display holding your mouse cursor so typing focus never changes, with drag-and-drop, click-to-open, swipe-to-dismiss, and hover buttons to move a throwaway capture straight to Trash.
- Because macOS itself captures the screen, SnapClip requires no Screen Recording or Accessibility permissions, opens no network sockets, and restores your original `screencapture` defaults on `snapclip uninstall`.

Source, architecture details, and Homebrew tap (`brew install aklkbqx/snapclip/snapclip`): https://github.com/aklkbqx/snapclip
```

---

### 4.3 Reddit: `r/swift` and `r/commandline`

- **Title:** `SnapClip: Zero-dependency Swift 6 macOS daemon that copies native screenshots to clipboard + Desktop via vnode watching (no Screen Recording TCC)`
- **Body:**

```markdown
I published **SnapClip**, a small Swift 6 CLI and LaunchAgent that lets stock macOS `Cmd+Shift+3 / 4 / 5` copy PNG + TIFF to the clipboard, save the file to `~/Desktop` without the 5-second `show-thumbnail` delay, and show a non-activating AppKit preview card.

Technical details that might be interesting to Swift / macOS folks:

* **No Screen Recording or Accessibility TCC:** Instead of `CGWindowListCreateImage` or `ScreenCaptureKit`, `snapclip install` points `com.apple.screencapture` at `~/.local/state/snapclip/staging` with `show-thumbnail = 0` (after backing up existing keys for `snapclip uninstall`).
* **Serial `O_EVTONLY` watcher + `ImageIO` verification:** `CaptureWatcher` listens for `.write`, `.extend`, `.attrib`, and `.rename` vnode events, sorts staged captures oldest-first so rapid bursts preserve clipboard order, and checks image trailers + `CGImageSource` status before touching the pasteboard.
* **Non-activating AppKit preview (`SnapClipUI`):** Uses an `NSPanel` configured with `.borderless` and `.nonactivatingPanel` positioned on the display containing `NSEvent.mouseLocation`, supporting `NSDraggingSource` file drags, hover timer pause, and `FileManager.trashItem` quick delete.
* **Testable core without external packages:** `DefaultsStoring`, `PasteboardWriting`, `CapturePostProcessor`, and `CaptureActionSink` are protocol-isolated in `SnapClipCore` with 24 Swift Testing unit tests.

Install on macOS 14+:

```sh
brew install aklkbqx/snapclip/snapclip
snapclip install
```

Repo (MIT): https://github.com/aklkbqx/snapclip
```

---

### 4.4 X (Twitter) / Bluesky / Threads (Attach `dist/media/showcase.mp4`)

```text
Built SnapClip for macOS (open-source, Swift, MIT):

Press Cmd+Shift+4 once -> copies PNG+TIFF to clipboard, saves to Desktop with zero 5s delay, and shows a non-blocking corner card (drag out, click to open, or hover to Trash).

Requires zero Screen Recording permissions.

brew install aklkbqx/snapclip/snapclip
https://github.com/aklkbqx/snapclip
```
