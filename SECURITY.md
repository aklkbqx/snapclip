# Security policy

SnapClip watches a configured local staging directory, reads screenshots onto the macOS clipboard, and manages user-scoped `LaunchAgent` and `com.apple.screencapture` preferences.

## Safe operation

- SnapClip opens no network sockets, makes no outbound HTTP requests, and collects no telemetry (`snapclip donate --open` only opens the GitHub Sponsors URL in your default browser when explicitly invoked).
- Screen captures are staged in user-owned directories (`~/.local/state/snapclip/staging`) and moved with standard macOS file APIs; deleting from the preview panel moves files to macOS Trash instead of unlinking them immediately.
- Clipboard writes copy pixels only and clear previous pasteboard items cleanly before calling `writeObjects`.
- Do not point `stagingDirectory` or `destinationDirectory` at untrusted shared directories where another local user can drop symlinks.

## Reporting a vulnerability

Do not open a public issue for an undisclosed vulnerability. Report privately through GitHub private vulnerability reporting on the repository once published, including macOS version, steps to reproduce, and affected file paths without personal screenshots or tokens.
