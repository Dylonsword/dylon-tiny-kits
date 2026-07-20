<div align="center">

# dylon-tiny-kits

### Small tools I use myself before releasing them for everyone else

[![CI](https://github.com/Dylonsword/dylon-tiny-kits/actions/workflows/ci.yml/badge.svg)](https://github.com/Dylonsword/dylon-tiny-kits/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-2f855a.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-3b4252.svg)](#platform-support)

[简体中文](README.md) · **English** · [GitHub](https://github.com/Dylonsword/dylon-tiny-kits) · [Gitee](https://gitee.com/dylontfif/dylon-tiny-kits)

</div>

This repository contains practical tools and Agent Skills that I use and refine in real AI-assisted development workflows. It is intentionally not a large catalog. Every published project should be understandable, installable, and removable on its own, with honest compatibility notes and privacy-conscious defaults.

## Available Projects

| Project | In one sentence | Coverage | Status |
| --- | --- | --- | --- |
| [AI Session Notifier](tools/ai-session-notifier/README.md) | Shows desktop alerts when Codex, Claude Code, or Kimi Code needs attention, then tries to return to the originating session. | macOS / Linux / Windows; see the matrix below | Beta, used daily |

Standalone Agent Skills belong in [`skills/`](skills/). Skills that only operate one tool stay with that tool. Work that is not ready for an independent release is not listed just to make the catalog look larger.

## Fastest Install

### Ask an Agent

Send this to Codex, Claude Code, Kimi Code, or another coding agent:

```text
Install AI Session Notifier from dylon-tiny-kits:
https://github.com/Dylonsword/dylon-tiny-kits/tree/main/tools/ai-session-notifier

Read the README section for coding agents first. Install only adapters supported
on this operating system, and do not modify a package manager without approval.
Run doctor and the --dry-run tests afterward, then report the results.
```

The tool documentation includes an installation contract for coding agents, so users do not need to remember hook, plugin-cache, or configuration paths.

### Manual macOS Install

```zsh
git clone https://github.com/Dylonsword/dylon-tiny-kits.git
cd dylon-tiny-kits
tools/ai-session-notifier/scripts/install.sh --all --dry-run
tools/ai-session-notifier/scripts/install.sh --all
```

The installer reports any Kimi Code plugin trust step that still needs user confirmation. See the [complete AI Session Notifier documentation](tools/ai-session-notifier/README.md) for Linux, Windows, per-adapter installation, and removal.

## AI Session Notifier

> When several VS Code windows, a Codex Desktop task, Claude Code, and Kimi Code are running at once, checking every window should not be the only way to learn which session finished and which one needs approval.

AI Session Notifier connects coding-agent lifecycle hooks to one local notification, routing, and bounded-history layer.

### What It Does

| Capability | Behavior |
| --- | --- |
| Prominent alerts | Handles supported turn-stop, permission, idle, failure, and background-task events. |
| One-action return | Chooses Codex Desktop, VS Code, Claude Code, or the originating Kimi terminal host. |
| Multi-window routing | Uses workspace and session metadata to raise the best matching window before opening the session link. |
| Smart noise control | Deduplicates events and suppresses Codex permission alerts already handled by automatic review. |
| English and Chinese | Follows the system language by default or can be fixed to English or Simplified Chinese. |
| Local history | Keeps a retention- and size-bounded event ledger plus only the latest route for each session. |
| Diagnosable and removable | Includes status, doctor, cleanup, dry-run testing, and complete removal commands. |

### Privacy Defaults

- The notifier makes no network calls; its state stays on the local machine.
- Assistant-message excerpts, raw hook payloads, and debug logs are off by default.
- Unix configuration directories use `0700`; configuration and event files use `0600`.
- Provider logos are not redistributed. Adapters read icons from locally installed official applications or extensions.

### Limits Worth Knowing

- `Stop` means the current turn stopped; it does not prove that a long-running task is finally complete.
- VS Code and host applications do not expose stable exact-window APIs in every environment, so routing remains best effort.
- Kimi Code has no documented session deep link, so its adapter can only return to the likely terminal host and workspace.
- Linux and Windows have automated coverage, but some desktop behavior still needs broader field testing.

[Full documentation](tools/ai-session-notifier/README.md) · [Changelog](tools/ai-session-notifier/CHANGELOG.md) · [Configuration example](tools/ai-session-notifier/config.example.json)

## Platform Support

| Platform | Codex | Claude Code | Kimi Code |
| --- | --- | --- | --- |
| macOS | Tested with Codex Desktop, VS Code, local icons, and best-effort multi-window focus | Tested | Native plugin tested |
| Linux | Not packaged | Adapter and automated tests included; more desktop testing is needed | Adapter and automated tests included; desktop testing is needed |
| Windows | Not packaged | PowerShell dialog and window focus included; field testing is still needed | PowerShell dialog and window focus included; field testing is still needed |

## Repository Layout

```text
tools/       Independently installable utilities and their agent adapters
skills/      Agent Skills reusable outside one specific tool
templates/   Reusable project templates for people and agents
docs/        Repository-wide release and maintenance standards
```

Each tool keeps its implementation, adapters, tests, documentation, and changelog in one directory. Cloning the full toolbox is convenient, while using a single project does not pull in hidden dependencies.

## Release Principles

- **Solve a real problem first**: use and validate a tool before packaging it for others.
- **Respect privacy by default**: collect the least local state needed; sensitive records require explicit opt-in.
- **Keep install and removal symmetric**: document what changes and provide previewable removal paths.
- **State limits honestly**: automated coverage is not field testing, and best-effort routing is not exact routing.
- **Be agent-friendly**: document how an agent can install and verify the project safely, not only how a person can do it manually.

## Feedback

Maintained by [Dylon Cai](https://github.com/Dylonsword). Reproducible issues and adapter feedback are welcome on GitHub. If one of these tools is useful, a Star is a simple signal about which direction is worth continuing.

## License

Unless a subproject states otherwise, this repository is available under the [MIT License](LICENSE). Codex, Claude, Kimi, and related marks belong to their respective owners. This community project is not affiliated with or endorsed by OpenAI, Anthropic, or Moonshot AI.
