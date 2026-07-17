#!/bin/zsh
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
TOOL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APP_CONFIG_DIR="${AI_SESSION_NOTIFIER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-session-notifier}"
APP_DATA_DIR="${AI_SESSION_NOTIFIER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-session-notifier}"
BIN_DIR="${AI_SESSION_NOTIFIER_BIN_DIR:-$HOME/.local/bin}"

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--all] [--codex] [--claude] [--kimi] [--purge] [--dry-run]

Uninstalls AI Session Notifier adapters. Management commands, shared config,
and ledger files are left in place unless --purge is explicitly supplied.
EOF
}

assert_safe_purge_path() {
  local path="$1"
  if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" || "$path" == "." || "$path" == ".." ]]; then
    echo "Refusing unsafe purge path: ${path:-<empty>}" >&2
    exit 2
  fi
}

remove_codex=false
remove_claude=false
remove_kimi=false
purge=false
dry_run=false

if [[ $# -eq 0 ]]; then
  remove_codex=true
  remove_claude=true
  remove_kimi=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      remove_codex=true
      remove_claude=true
      remove_kimi=true
      ;;
    --codex)
      remove_codex=true
      ;;
    --claude|--claude-code)
      remove_claude=true
      ;;
    --kimi|--kimi-code)
      remove_kimi=true
      ;;
    --purge)
      purge=true
      ;;
    --dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

find_claude() {
  if command -v claude >/dev/null 2>&1; then
    command -v claude
    return 0
  fi
  local candidates
  candidates=("$HOME"/.nvm/versions/node/*/bin/claude(N))
  if (( ${#candidates[@]} > 0 )); then
    printf '%s\n' "${candidates[-1]}"
    return 0
  fi
  return 1
}

if [[ "$remove_codex" != true && "$remove_claude" != true && "$remove_kimi" != true ]]; then
  remove_codex=true
  remove_claude=true
  remove_kimi=true
fi

if [[ "$remove_kimi" == true ]]; then
  echo "Remove the trusted plugin through Kimi Code so its registry stays consistent:"
  echo "/plugins disable ai-session-notifier"
  echo "/plugins remove ai-session-notifier"
  echo "/reload"
  if [[ "$dry_run" == true ]]; then
    echo "Would remove Kimi runtime adapters from: $APP_DATA_DIR/bin"
  else
    /bin/rm -f "$APP_DATA_DIR/bin/kimi-session-notify" "$APP_DATA_DIR/bin/kimi-session-notify.ps1"
  fi
fi

if [[ "$remove_codex" == true ]]; then
  codex_args=()
  [[ "$dry_run" == true ]] && codex_args+=(--dry-run)
  "$TOOL_DIR/codex-plugin/scripts/uninstall.sh" "${codex_args[@]}"
fi

if [[ "$remove_claude" == true ]]; then
  if claude_bin="$(find_claude)"; then
    if [[ "$dry_run" == true ]]; then
      echo "Would uninstall Claude Code plugin: ai-session-notifier@dylon-tiny-kits"
    else
      claude_dir="$(cd -- "$(dirname -- "$claude_bin")" && pwd)"
      PATH="$claude_dir:$PATH" "$claude_bin" plugin uninstall ai-session-notifier@dylon-tiny-kits --scope user --keep-data || true
    fi
  else
    echo "Claude Code CLI not found; skipped Claude Code adapter uninstall." >&2
  fi
  if [[ "$dry_run" == true ]]; then
    echo "Would remove Claude runtime adapters from: $APP_DATA_DIR/bin"
  else
    /bin/rm -f "$APP_DATA_DIR/bin/ai-session-notify" "$APP_DATA_DIR/bin/ai-session-notify.ps1" "$APP_DATA_DIR/bin/ai-session-notify.cmd"
  fi
fi

if [[ "$purge" == true ]]; then
  if [[ "$dry_run" == true ]]; then
    echo "Would purge private config: $APP_CONFIG_DIR"
    echo "Would purge local data: $APP_DATA_DIR"
    echo "Would remove manager and report commands from: $BIN_DIR"
  else
    assert_safe_purge_path "$APP_CONFIG_DIR"
    assert_safe_purge_path "$APP_DATA_DIR"
    /bin/rm -rf "$APP_CONFIG_DIR" "$APP_DATA_DIR"
    /bin/rm -f "$BIN_DIR/ai-session-notifier" "$BIN_DIR/ai-session-report"
    echo "Purged AI Session Notifier config and local data."
  fi
fi

if [[ "$dry_run" == true ]]; then
  echo "AI Session Notifier uninstall dry run complete; no files changed."
else
  echo "AI Session Notifier uninstall complete."
fi
