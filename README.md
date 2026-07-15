# dylon-tiny-kits

Small, practical tools and reusable agent skills by Dylon Cai.

[简体中文](README.zh-CN.md)

Each project is designed to be understandable, installable, and removable on
its own, with clear compatibility notes and privacy-conscious defaults.

## Tools

Available tools are indexed here as they are added.

## Skills

Reusable, agent-facing workflows live under [`skills/`](skills/). A skill
belongs there when it is useful independently of a particular tool. Skills
that only operate one tool stay with that tool.

## Repository Layout

```text
tools/       Standalone utilities and their agent adapters
skills/      Reusable agent workflows
templates/   Reusable human and agent project templates
docs/        Repository-wide standards
```

## Project Principles

Projects remain self-contained: tool-specific documentation, tests, adapters,
and changelogs stay beside the tool. Workflows that are independently useful
across projects live under `skills/`.

## License

Unless a subproject states otherwise, code in this repository is available
under the [MIT License](LICENSE).
