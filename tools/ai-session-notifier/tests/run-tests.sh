#!/usr/bin/env sh
set -eu

tool_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_root=$(CDPATH= cd -- "$tool_root/../.." && pwd)
cd "$repo_root"

sh -n "$tool_root/claude-code-plugin/bin/ai-session-notify"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$tool_root/scripts/install.sh"
  zsh -n "$tool_root/scripts/uninstall.sh"
  zsh -n "$tool_root/codex-plugin/scripts/install.sh"
  zsh -n "$tool_root/codex-plugin/scripts/uninstall.sh"
  zsh -n "$tool_root/codex-plugin/scripts/codex-notify.sh"
fi

python3 -m unittest discover -s "$tool_root/tests" -p 'test_*.py' -v
