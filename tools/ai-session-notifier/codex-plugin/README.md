# Codex Adapter

macOS notification hooks for Codex:

- `Stop`: the current Codex turn stopped.
- `PermissionRequest`: Codex is waiting for an approval decision.

`Stop` is turn-scoped and must not be presented as proof that the whole task is
finished. A small heuristic labels messages that mention monitoring/loading as
`Codex 已进入观察窗口`. Set `noise.observationMode` to `quiet` to record those
events without showing a desktop notification.

Permission alerts use `noise.permissionMode: smart` by default. Current Codex
hook payloads do not directly expose whether the effective reviewer is the user
or automatic review, so the adapter falls back to the current task transcript's
latest structured `approvals_reviewer` value. It suppresses only confirmed
`auto_review`/`guardian_subagent` or `bypassPermissions` events. Unknown and
user-reviewed requests remain visible. Use `notify` to always alert or `quiet`
to silence all Codex permission events. Transcript message bodies are never
copied into notifier state.

See the [shared AI Session Notifier README](../README.md) for privacy, storage,
configuration, platform support, and complete removal.

Notification titles, messages, and buttons follow the system language by
default. Set shared `notifications.locale` or `AI_SESSION_NOTIFIER_LOCALE` to
`zh-CN` or `en` to override it.

## Install

From the repository root:

```zsh
tools/ai-session-notifier/codex-plugin/scripts/install.sh --test
```

The installer does not install packages by default. Enable clickable
Notification Center banners with:

```zsh
tools/ai-session-notifier/codex-plugin/scripts/install.sh --install-deps --test
```

It will:

- back up `~/.codex/hooks.json`;
- merge its entries without removing unrelated hooks;
- install a private `~/.codex/hooks/codex-notify.sh`;
- install `ai-session-notifier` and `ai-session-report` in `~/.local/bin`;
- initialize a private versioned config and migrate older route data;
- remove legacy raw-payload and copied-logo files from the hook directory.

After a hook update, Codex may ask to review it. Choose `Trust all and continue`
only after reviewing the local script and expected paths.

## Session Routing

When `terminal-notifier` is available, the banner and visible dialog can open:

- `vscode://openai.chatgpt/local/<thread_id>` for VS Code sessions;
- `codex://threads/<thread_id>` for Codex Desktop sessions.

For VS Code, the macOS opener first tries to raise a window matching the saved
workspace, opens that workspace, opens the thread URL, and raises the matching
window again. This can require Accessibility permission and remains best effort
because VS Code does not expose a stable exact-window id in this deep link.

The icon is read from the local ChatGPT/Codex application, then from the
official OpenAI VS Code extension. `notifications.codexIconPath` can override
the lookup. No Codex logo is bundled.

## Local Data

Default paths:

```text
~/.config/ai-session-notifier/config.json
~/.local/share/ai-session-notifier/events.jsonl
~/.local/share/ai-session-notifier/sessions.json
```

Assistant-message excerpts, raw payload snapshots, and debug logs are disabled
by default. To troubleshoot, explicitly enable `debug.logEnabled` or
`debug.saveRawPayload`, reproduce once, and disable it again afterward.
Suppressed automatic-review events remain in `events.jsonl` with
`approvalReviewer`, `permissionMode`, and `suppressionReason` fields.

## Uninstall

```zsh
tools/ai-session-notifier/codex-plugin/scripts/uninstall.sh
```

This removes only this adapter's hook entries and runtime script. Shared data,
management commands, backups, and `terminal-notifier` remain in place. Use the
shared uninstaller with `--purge` for complete removal.
