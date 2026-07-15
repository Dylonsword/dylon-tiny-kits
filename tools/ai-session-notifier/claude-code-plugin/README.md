# Claude Code Adapter

Claude Code plugin for AI Session Notifier. It listens for:

- `permission_prompt`: Claude Code needs an approval decision;
- `idle_prompt`: the current turn is idle and waiting for attention.

An idle prompt is not proof that a larger multi-step task is complete. See the
[shared README](../README.md) for privacy defaults, storage, reporting, and
cross-tool behavior.

## Install

Load directly for one session:

```sh
claude --plugin-dir /absolute/path/to/dylon-tiny-kits/tools/ai-session-notifier/claude-code-plugin
```

Install persistently from the repository marketplace:

```text
claude plugin marketplace add /absolute/path/to/dylon-tiny-kits
claude plugin install ai-session-notifier@dylon-tiny-kits --scope user
```

Update an existing install:

```text
claude plugin update ai-session-notifier@dylon-tiny-kits --scope user
```

Validate the package:

```text
claude plugin validate /absolute/path/to/dylon-tiny-kits/tools/ai-session-notifier/claude-code-plugin
```

## Runtime Files

- `hooks/hooks.json`: Claude Code notification hook declarations.
- `bin/ai-session-notify`: macOS/Linux shell adapter.
- `bin/ai-session-notify.cmd`: Windows command launcher.
- `bin/ai-session-notify.ps1`: Windows dialog, ledger, cleanup, and opener.

## Platform Notes

- macOS uses `terminal-notifier` when available, with AppleScript fallback. The
  icon comes from a local Claude application or the official Anthropic VS Code
  extension; `notifications.claudeIconPath` can override it.
- Linux uses `notify-send` when available and falls back to stderr.
- Windows uses a PowerShell dialog and a named mutex for concurrent ledger and
  route updates. It includes best-effort VS Code window focus through window
  titles and user32.
- `claude-cli://open` can open Claude Code for a directory, but host behavior is
  not guaranteed to focus an exact already-running session.

Linux and Windows paths have automated checks; more desktop field testing is
still welcome.

## Smoke Tests

macOS/Linux:

```sh
printf '%s\n' '{"hook_event_name":"Notification","notification_type":"idle_prompt","cwd":"/tmp/demo"}' | bin/ai-session-notify
```

Windows:

```cmd
echo {"hook_event_name":"Notification","notification_type":"idle_prompt","cwd":"C:\\work\\demo"} | bin\ai-session-notify.cmd
```

Set `AI_SESSION_NOTIFIER_DRY_RUN=1` to exercise ledger/routing logic without
showing a desktop dialog.
