# AI Session Notifier

**AI Session Notifier** is a local notification and return-to-session tool for
Codex, Claude Code, and Kimi Code CLI. Its Codex adapter is packaged as
`codex-notify-hooks`.

[简体中文](README.zh-CN.md)

## What It Does

When an AI coding session stops or needs approval, the tool shows a prominent
desktop alert. One **Open session** action then attempts to return to the app,
workspace, and thread that produced the event.

| Capability | Behavior |
| --- | --- |
| Codex alerts | Notifies on `Stop` and `PermissionRequest`. |
| Claude Code alerts | Notifies on permission and idle events. |
| Kimi Code alerts | Notifies on turn stops, permission requests, failures, and completed background tasks. |
| Session return | Chooses Codex Desktop, VS Code, Claude Code, or the originating Kimi terminal host. |
| Multi-window routing | Tries to raise the matching VS Code workspace before opening the thread link. |
| Noise control | Deduplicates repeated alerts and identifies likely observation windows. |
| Local history | Keeps a bounded event ledger and only the latest route for each session. |
| Operations | Provides status, diagnostics, cleanup, dry-run tests, and reports. |

A Codex or Kimi Code `Stop` event means the current turn stopped. It does
**not** prove that a larger task or goal is complete. Likewise, a Claude Code
`idle_prompt` only means that the current session is waiting.

## Install

Clone the repository, enter its root directory, and choose the adapters needed
on that machine.

### macOS: all adapters

```zsh
tools/ai-session-notifier/scripts/install.sh --all
```

Install only one adapter:

```zsh
tools/ai-session-notifier/scripts/install.sh --codex
tools/ai-session-notifier/scripts/install.sh --claude
tools/ai-session-notifier/scripts/install.sh --kimi
```

Verify the installation without showing test UI:

```zsh
"$HOME/.local/bin/ai-session-notifier" doctor
"$HOME/.local/bin/ai-session-notifier" test --tool all --dry-run
```

`terminal-notifier` is optional. The installer never changes Homebrew by
default. To install that dependency for clickable Notification Center banners:

```zsh
tools/ai-session-notifier/scripts/install.sh --all --install-deps
```

The Claude CLI lookup supports the active `PATH` and common nvm installations.

### Kimi Code native plugin

Kimi Code plugin hooks require CLI `0.20.1` or newer. Check with
`kimi --version`, then start Kimi Code and run:

```text
/plugins install /absolute/path/to/dylon-tiny-kits/tools/ai-session-notifier/kimi-code-plugin
/plugins enable ai-session-notifier
/reload
```

Kimi asks the user to trust a local third-party plugin. The unified installer
prints these commands but does not bypass that interactive review. See the
[Kimi adapter README](kimi-code-plugin/README.md) for event and routing details.
Kimi Code for VS Code `0.6.0` and newer uses the in-process CLI engine and the
same `KIMI_CODE_HOME`; install the plugin through an up-to-date CLI, then reload
the VS Code window so that surface can load it too.

### Linux or Windows: Claude Code

The Codex adapter is currently macOS-only. The repository root is a Claude Code
marketplace, so install the Claude adapter with its CLI:

```text
claude plugin marketplace add /absolute/path/to/dylon-tiny-kits
claude plugin install ai-session-notifier@dylon-tiny-kits --scope user
```

For an existing installation:

```text
claude plugin update ai-session-notifier@dylon-tiny-kits --scope user
```

On Windows, run these commands in PowerShell or Command Prompt. Claude Code
automatically selects `bin/ai-session-notify.cmd`.

## Installation Instructions for Coding Agents

> This section is an execution contract for Codex, Claude Code, Kimi Code, and
> other coding agents when a user asks them to install or configure this tool.
> Keep the work inside the cloned `dylon-tiny-kits` repository and the
> documented user-level paths.

1. Resolve the repository root from the current clone. Do not assume the
   maintainer's `/Users/...` path. Confirm that
   `tools/ai-session-notifier/tool.json` exists.
2. Detect the operating system and requested adapters. Codex is supported on
   macOS; Claude Code and Kimi Code are supported on macOS, Linux, and Windows.
   Do not claim that Codex installation is supported on Linux or Windows.
3. On macOS, preview changes first:

   ```zsh
   tools/ai-session-notifier/scripts/install.sh --all --dry-run
   ```

4. Run `--all`, `--codex`, `--claude`, or `--kimi` according to the user's
   request. Never add `--install-deps` unless the user explicitly approved
   package-manager changes.
5. On Linux/Windows, install or update
   `ai-session-notifier@dylon-tiny-kits` through the Claude CLI commands above. Do
   not edit Claude plugin caches manually.
6. For Kimi Code, require version `0.20.1` or newer and use `/plugins install`
   with the local `kimi-code-plugin` directory. Let the user accept Kimi's
   third-party trust prompt, then run `/plugins enable ai-session-notifier` and
   `/reload`. Do not edit Kimi's managed plugin registry manually.
7. Do not overwrite `~/.codex/hooks.json`. Use the installer, which backs up and
   merges only this tool's entries. Do not use `sudo`.
8. Validate with these non-UI checks after installation:

   ```sh
   "$HOME/.local/bin/ai-session-notifier" doctor
   "$HOME/.local/bin/ai-session-notifier" test --tool all --dry-run
   ```

   When the installed CLI is unavailable, run the source command with Python
   3.9 or newer:

   ```sh
   python3 tools/ai-session-notifier/scripts/ai-session-notifier doctor
   python3 tools/ai-session-notifier/scripts/ai-session-notifier test --tool all --dry-run
   ```

9. Do not enable message excerpts, raw payload capture, or debug logging unless
   the user explicitly requests that privacy tradeoff. Never run uninstall
   `--purge` as part of installation or troubleshooting.
10. Report the installed adapters, version, paths changed, `doctor` result, and
    any remaining warning. Tell the user that Claude Code must restart after a
    plugin update, Kimi Code needs `/reload` or a new session, and Codex may ask
    them to review the changed hook in a new task.

A real visible test can be sent with `ai-session-notifier test --tool <tool>`
when the user asks to see the popup. The default agent verification should use
`--dry-run` so it does not interrupt the desktop.

## Privacy Defaults

No network service is used by the notifier. All state stays on the local
machine.

| Behavior | Default |
| --- | --- |
| Save assistant-message excerpts | Off |
| Save raw hook payloads | Off |
| Debug logging | Off |
| Event retention | 30 days |
| Event ledger size | 5 MiB maximum |
| Unix config/data permissions | Owner only (`0700` directories, `0600` files) |

The ledger still contains routing metadata such as tool name, event category,
workspace path, session/thread id, target URL, and notification title. Disable
it with `ledger.enabled`, or purge it with the uninstall command if that
metadata is sensitive in your environment.

When upgrading an older install, schema 2 removes historical assistant-message
excerpts unless `ledger.includeMessageExcerpt` was already explicitly enabled.

## Management Commands

The macOS installer places these commands in `~/.local/bin`:

```sh
ai-session-notifier status
ai-session-notifier doctor
ai-session-notifier cleanup --dry-run
ai-session-notifier cleanup
ai-session-notifier test --tool all
ai-session-report --hours 24
```

Commands can also be run directly from a clone with Python 3.9 or newer:

```sh
python3 tools/ai-session-notifier/scripts/ai-session-notifier doctor
python3 tools/ai-session-notifier/scripts/ai-session-report --hours 24
```

Add `--json` to `init`, `status`, `doctor`, `cleanup`, or the report command for
machine-readable output.

## Routing Model

The latest route for each session is stored in `sessions.json`. A notification
uses hook metadata to choose Codex Desktop, VS Code, or Claude Code without
asking the user to remember where the task started. Kimi Code records the
originating terminal/IDE host and workspace.

For a VS Code Codex session on macOS, the opener:

1. tries to raise a window whose title matches the saved workspace path/name;
2. asks VS Code to open that workspace;
3. opens `vscode://openai.chatgpt/local/<thread_id>`;
4. raises the matching window again.

Codex Desktop uses `codex://threads/<thread_id>`. Claude Code uses its
`claude-cli://open` directory link. Windows includes a title-matching/user32
VS Code opener in the Claude adapter. Kimi Code has no documented session deep
link, so its adapter activates the originating terminal or VS Code app and
tries to raise a window matching the workspace title.

Routing is deliberately best effort. VS Code and host applications do not
expose a stable public deep-link parameter for selecting an exact existing
window in every configuration. On macOS, window raising also requires System
Events Accessibility permission. If matching fails, the workspace and session
URL still open normally.

## Platform Support

| Platform | Codex | Claude Code | Kimi Code CLI |
| --- | --- | --- | --- |
| macOS | Tested. `terminal-notifier` with AppleScript fallback; Codex App/VS Code routing and window focus. | Tested. `terminal-notifier` with AppleScript fallback and `claude-cli://` opener. | Native plugin tested with Kimi Code CLI `0.26.0`; requires CLI `0.20.1` or newer. Includes `terminal-notifier`/AppleScript and best-effort terminal or VS Code window focus. |
| Linux | Not currently packaged. | Shell adapter with `notify-send`; automated checks pass, desktop field testing is still needed. | Native plugin shell adapter with `notify-send`; desktop field testing is still needed. |
| Windows | Not currently packaged. | PowerShell dialog, locked local ledger, cleanup, and best-effort VS Code focus; automated checks included, desktop field testing is still needed. | Git Bash launcher with PowerShell dialog, locked ledger, and best-effort terminal/VS Code focus; desktop field testing is still needed. |

On macOS, adapters use icons from locally installed ChatGPT/Claude applications
or official OpenAI, Anthropic, and Moonshot AI VS Code extensions. Custom
per-tool paths can override that lookup. The repository does not redistribute
provider logo files.

## Config and Data

| Data | macOS/Linux | Windows |
| --- | --- | --- |
| Config | `~/.config/ai-session-notifier/config.json` | `%APPDATA%\ai-session-notifier\config.json` |
| Events | `~/.local/share/ai-session-notifier/events.jsonl` | `%LOCALAPPDATA%\ai-session-notifier\events.jsonl` |
| Session routes | `~/.local/share/ai-session-notifier/sessions.json` | `%LOCALAPPDATA%\ai-session-notifier\sessions.json` |

`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and the `AI_SESSION_NOTIFIER_*`
environment variables are respected. See [config.example.json](config.example.json)
for the complete schema.

Common settings:

- `notifications.enabled`: enable desktop notifications.
- `notifications.dialogs`: show the prominent macOS/Windows dialog.
- `notifications.sound`: enable notification sounds.
- `notifications.codexIconPath`, `notifications.claudeIconPath`, and
  `notifications.kimiIconPath`: override one tool's local icon.
- `notifications.iconPath`: shared fallback icon override.
- `noise.dedupeSeconds`: suppress repeated equivalent events.
- `noise.observationMode`: `notify` or `quiet` for likely Codex observation
  windows.
- `ledger.includeMessageExcerpt`: explicitly opt in to short assistant-message
  excerpts.
- `ledger.retentionDays` and `ledger.maxBytes`: local storage limits.
- `debug.saveRawPayload`: explicitly opt in to the latest raw hook payload.
- `routing.openWorkspaceFirst` and `routing.focusVSCodeWindow`: control
  best-effort VS Code routing.

Adapters apply cleanup at most once per day. The management command can run it
on demand and migrates the older append-only `session-registry.jsonl` format to
the compact registry.

## Uninstall

Remove adapters but retain management commands and local data:

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all
```

Preview complete removal:

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all --purge --dry-run
```

Remove adapters, configuration, ledger, registry, and installed commands:

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all --purge
```

The Codex uninstaller removes only this tool's `Stop` and `PermissionRequest`
entries and preserves unrelated hooks. Installers back up shared hook files
before changing them. Kimi Code plugin removal remains an interactive
`/plugins remove ai-session-notifier` action so its registry stays consistent.

## Development

```sh
tools/ai-session-notifier/tests/run-tests.sh
```

The test suite exercises redaction, permissions, retention, migration, Kimi
event semantics, concurrent ledger writes, installed CLI lookup, and
preservation of unrelated Codex hooks. GitHub Actions runs portable tests on
macOS, Linux, and Windows.

Codex, Claude, and Kimi are trademarks of their respective owners. This
community tool is not affiliated with or endorsed by OpenAI, Anthropic, or
Moonshot AI.
