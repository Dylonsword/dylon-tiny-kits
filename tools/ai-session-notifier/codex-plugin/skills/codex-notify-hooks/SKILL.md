---
name: codex-notify-hooks
description: Install, test, diagnose, uninstall, or explain the privacy-first AI Session Notifier adapter for Codex on macOS.
---

# Codex Notify Hooks

Use this skill when the user wants to install, test, update, uninstall, or understand this local notification hook package.

## Package Location

When working from a dylon-tiny-kits clone, the adapter lives at:

```text
tools/ai-session-notifier/codex-plugin
```

The installer writes runtime files into:

```text
~/.codex/hooks/codex-notify.sh
~/.codex/hooks.json
```

## Commands

Install and send a test notification:

```bash
tools/ai-session-notifier/codex-plugin/scripts/install.sh --test
```

Install `terminal-notifier` through Homebrew for clickable banners:

```bash
tools/ai-session-notifier/codex-plugin/scripts/install.sh --install-deps
```

Uninstall:

```bash
tools/ai-session-notifier/codex-plugin/scripts/uninstall.sh
```

Diagnose an installed setup:

```bash
ai-session-notifier doctor
```

## Trust Step

After installation, Codex may ask to review hooks. Choose:

```text
Trust all and continue
```

Do not suggest bypassing hook trust for normal interactive use.

## Behavior

- `Stop` notifications use the title `Codex 本轮已停下`.
- Observation-window `Stop` notifications use the title `Codex 已进入观察窗口`.
- `PermissionRequest` notifications use the title `Codex 正在等你确认权限`.
- Events are written to `~/.local/share/ai-session-notifier/events.jsonl`.
- Latest session routes are compacted in `~/.local/share/ai-session-notifier/sessions.json`.
- Runtime config lives at `~/.config/ai-session-notifier/config.json`.
- Message excerpts, raw payload snapshots, and debug logs are disabled by default.
- Storage is automatically bounded by retention days and maximum bytes.
- `routing.focusVSCodeWindow` enables a macOS System Events best-effort window
  raise for VS Code sessions before opening the thread deep link.
- When `terminal-notifier` is available, notification clicks open the best available deep link:
  - `vscode://openai.chatgpt/local/<thread_id>` for VS Code-originated threads.
  - `codex://threads/<thread_id>` for Codex Desktop-originated threads.
- Without `terminal-notifier`, the package falls back to plain macOS `osascript` notifications.
- `Stop` means the current turn stopped; never describe it as guaranteed whole-task completion.

## Safety

The installer backs up `~/.codex/hooks.json` before changing it and merges only
this package's hook entries. It should not remove unrelated hooks. Package
installation is opt-in, and the installer supports `--dry-run`.
