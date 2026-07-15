# Project Standard

This repository stores small projects that remain easy to review, install,
remove, and publish.

## Tool Structure

Each tool lives under `tools/<tool-name>/` and should include:

- `README.md`: purpose, compatibility, installation, removal, and caveats.
- `tool.json`: name, version, author, supported surfaces, and platforms.
- `CHANGELOG.md`: user-visible changes by release.
- `tests/`: focused automated verification.
- App-specific adapters in separate folders such as `codex-plugin/` or
  `claude-code-plugin/`.

Reusable standalone skills live under `skills/<skill-name>/`. A skill required
only by one tool stays inside that tool's adapter or package.

## Compatibility

- Prefer portable scripts and explicit fallbacks.
- Document macOS, Linux, and Windows behavior separately.
- Mark untested platforms clearly in metadata and documentation.
- Do not write to a user's home directory at package time. Installation may do
  so only after the user explicitly runs an installer.

## Privacy and Safety

- Collect only what the workflow needs. Message bodies, prompts, raw hook
  payloads, and secrets must be off by default.
- Document persistent paths, retention policies, cleanup, and purge commands.
- Use private file permissions where the platform supports them.
- Make package-manager changes opt-in and provide dry-run behavior where useful.
- Merge shared configuration carefully and preserve unrelated entries.
- Retain user data on uninstall unless an explicit purge option is provided.
- Do not redistribute third-party logos without clear permission. Prefer icons
  already installed with the provider's application or extension.

## Release Checklist

- Run syntax checks and the project's complete test suite.
- Validate manifests with vendor validators when available.
- Test install and uninstall paths in an isolated temporary home.
- Confirm unrelated hooks and settings survive install and uninstall.
- Review privacy defaults, permissions, retention, and destructive actions.
- Update both language entry points, metadata, and the project changelog.
- Update the root project index.
- Commit with the configured repository identity.
