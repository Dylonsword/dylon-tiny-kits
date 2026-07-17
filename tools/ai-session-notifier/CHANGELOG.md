# Changelog

All notable changes to AI Session Notifier are documented here.

## [0.5.2] - 2026-07-17

### Added

- Added `noise.permissionMode` with `smart`, `notify`, and `quiet` values plus
  the `AI_SESSION_NOTIFIER_PERMISSION_MODE` environment override.
- Added Codex effective reviewer detection from future hook payload fields or
  the current task transcript's latest structured `approvals_reviewer` state.
- Added approval reviewer/mode diagnostics to Codex ledger entries.

### Changed

- Suppress Codex permission UI only when automatic review or bypass mode is
  confirmed; user-reviewed and unknown permission requests remain visible.
- Keep Claude Code and Kimi Code permission notifications visible because their
  configured events mean the tool is actually about to wait for a person.

## [0.5.1] - 2026-07-16

### Added

- Added automatic English and Simplified Chinese notification text for Codex,
  Claude Code, and Kimi Code on macOS, Linux, and Windows adapters.
- Added `notifications.locale` with `auto`, `zh-CN`, and `en` values, plus the
  `AI_SESSION_NOTIFIER_LOCALE` environment override.

### Changed

- Localized prominent-dialog buttons and Claude Code's workspace-return prompt.
- Kept Traditional Chinese system locales on the English fallback until a
  dedicated Traditional Chinese translation is available.

## [0.5.0] - 2026-07-16

### Added

- Added a native Kimi Code plugin for `Stop`, `PermissionRequest`,
  `StopFailure`, and completed background-task notifications.
- Added Kimi Code status, version compatibility checks, dry-run tests, local
  icon discovery, bounded ledger entries, and runtime adapter diagnostics.
- Added best-effort return to the originating terminal or VS Code window on
  macOS and Windows.

### Changed

- Extended shared configuration with `notifications.kimiIconPath`.
- Updated the unified installer and uninstaller with Kimi-specific setup and
  removal guidance while preserving Kimi Code's interactive plugin trust flow.

## [0.4.1] - 2026-07-14

### Fixed

- Restored Codex dialog icons by resolving the dedicated Codex asset from the
  locally installed ChatGPT app, with the official OpenAI VS Code extension as
  fallback.
- Added equivalent local Claude app/Anthropic extension icon discovery and a
  visible image in the Windows Claude Code dialog.

### Changed

- Unified repository, plugin, and future Git author identity as `Dylon Cai`.
- Added per-tool `codexIconPath` and `claudeIconPath` overrides plus icon
  diagnostics.

## [0.4.0] - 2026-07-14

### Added

- `ai-session-notifier` management CLI with `init`, `status`, `doctor`,
  `cleanup`, and adapter test commands.
- Compact session registry, automatic retention/size cleanup, installer dry
  runs, and machine-readable status/report output.
- Automated macOS, Linux, and Windows checks through GitHub Actions.
- Windows Claude Code ledger locking and best-effort VS Code window focus.

### Changed

- Disabled assistant-message excerpts, raw payload snapshots, and debug logs by
  default.
- Redacted historical assistant-message excerpts during schema 2 migration
  unless the user explicitly opted in to keeping them.
- Restricted local config and ledger permissions on Unix-like systems.
- Made Homebrew dependency installation opt-in with `--install-deps`.
- Improved nvm-aware Claude Code installation and XDG directory support.
- Switched session history from an append-only route file to a compact registry.
- Resolved provider icons from locally installed ChatGPT/Claude applications or
  their official VS Code extensions instead of bundling logo files.

### Removed

- Bundled Codex and Claude logo files. Runtime adapters now use locally installed
  application icons or an explicit user-configured icon.
