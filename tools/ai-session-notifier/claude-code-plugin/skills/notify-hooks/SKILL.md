---
description: Explain and maintain the AI session notification hooks for Claude Code.
---

# AI Session Notification Hooks

Use this skill when the user asks about this plugin, its hooks, or its platform
compatibility.

The plugin listens for Claude Code `Notification` hook events:

- `permission_prompt`: tells the user Claude Code is waiting for a permission
  decision.
- `idle_prompt`: tells the user the turn is idle and Claude Code is waiting for
  input. It does not necessarily mean a larger multi-step task is finally
  complete.

The notifier entrypoint is `bin/ai-session-notify` on macOS/Linux and
`bin/ai-session-notify.cmd` on Windows. The Windows launcher delegates to
`bin/ai-session-notify.ps1`.

Notification titles, messages, and buttons follow the system language by
default. English and Simplified Chinese are included. Set
`notifications.locale` to `auto`, `zh-CN`, or `en`, or use the
`AI_SESSION_NOTIFIER_LOCALE` environment override.

On macOS/Linux, events are written to the private shared AI Session Notifier ledger:

```text
~/.local/share/ai-session-notifier/events.jsonl
```

On Windows, the ledger defaults to:

```text
%LOCALAPPDATA%\ai-session-notifier\events.jsonl
```

Runtime config lives at:

```text
~/.config/ai-session-notifier/config.json
```

The latest route per session is stored in `sessions.json`. Message excerpts,
raw hook payloads, and debug logs are disabled by default. Events are limited by
the configured retention period and maximum ledger size.

Platform behavior:

- macOS: `terminal-notifier` with click-through when available, otherwise
  AppleScript notification.
- Linux: `notify-send` when available.
- Windows: PowerShell dialog, shared ledger, and best-effort VS Code window
  focusing through process window titles/user32.

Routing to an exact already-running session is not guaranteed by the host app.
Describe it as best effort. Use `AI_SESSION_NOTIFIER_DRY_RUN=1` for tests that
must not show UI.
