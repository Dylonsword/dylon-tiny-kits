# AI Session Notifier for Kimi Code

This is the native Kimi Code CLI adapter for AI Session Notifier. It uses
Kimi's lifecycle hooks and does not watch terminal output, session files, or
logs.

## Requirements

- Kimi Code CLI `0.20.1` or newer. Plugin-owned hooks were introduced in that
  release.
- macOS, Linux, or Windows. Windows uses the Git Bash shell required by Kimi
  Code and delegates notification UI to PowerShell.

Kimi Code for VS Code `0.6.0` and newer uses the in-process CLI engine and
shares `KIMI_CODE_HOME` with the terminal client. Install this plugin with an
up-to-date CLI, then reload the VS Code window to use the same hook there. The
legacy VS Code runtime is not supported.

Check the installed version:

```sh
kimi --version
```

## Install

Clone `dylon-tiny-kits`, start Kimi Code, and run the following inside its TUI:

```text
/plugins install /absolute/path/to/dylon-tiny-kits/tools/ai-session-notifier/kimi-code-plugin
/plugins enable ai-session-notifier
/reload
```

Kimi Code asks for confirmation before trusting a local third-party plugin.
Do not bypass that review. Local plugin installs are copied into Kimi's managed
plugin directory, so reinstall after editing the source.

Official references: [hooks](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html)
and [plugins](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/plugins.html).

## Events

| Kimi hook | Notification |
| --- | --- |
| `Stop` | The current turn stopped and is ready for review. |
| `PermissionRequest` | Kimi Code is waiting for an approval decision. |
| `StopFailure` | The current turn stopped because of an error. |
| `Notification` with `task.completed` | A background task finished. |

`Stop` describes one turn, not guaranteed completion of a larger goal or
multi-turn workflow.

Notification titles, messages, and buttons follow the system language by
default. Set shared `notifications.locale` or `AI_SESSION_NOTIFIER_LOCALE` to
`zh-CN` or `en` to override it.

## Return to Session

On macOS, both the system notification and the prominent dialog use the same
workspace-aware return callback. For VS Code, it sends the full saved working
directory through VS Code's bundled CLI so the editor can select the existing
workspace window. If that CLI is unavailable, it falls back to the previous
`AXRaise` and `AXMain` title match. Terminal-hosted sessions still activate
their originating terminal. Windows uses a similar title match across VS Code
and common terminal applications.

Kimi Code currently has no documented session deep link. The adapter can
therefore target the correct workspace window, but it cannot guarantee exact
selection between multiple Kimi history entries inside that same workspace.
The saved session id and workspace remain available in AI Session Notifier's
local registry.

## Privacy

The adapter uses the shared AI Session Notifier configuration and bounded local
ledger. Assistant-message excerpts and raw hook payloads are disabled by
default. See the parent [README](../README.md) for paths, retention, cleanup,
and icon overrides.

## Remove

Inside Kimi Code:

```text
/plugins disable ai-session-notifier
/plugins remove ai-session-notifier
/reload
```
