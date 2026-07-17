#!/bin/zsh
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
TOOL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$TOOL_DIR/../.." && pwd)"
APP_DATA_DIR="${AI_SESSION_NOTIFIER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-session-notifier}"
APP_CONFIG_DIR="${AI_SESSION_NOTIFIER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-session-notifier}"
BIN_DIR="${AI_SESSION_NOTIFIER_BIN_DIR:-$HOME/.local/bin}"
MANAGE_CLI="$BIN_DIR/ai-session-notifier"
REPORT_CLI="$BIN_DIR/ai-session-report"

usage() {
  cat <<'EOF'
Usage: install.sh [--all] [--codex] [--claude] [--kimi] [--test] [--install-deps] [--dry-run]

Installs AI Session Notifier adapters.

Options:
  --all      Prepare Codex, Claude Code, and Kimi Code adapters. This is the default.
  --codex    Install only the Codex hook adapter.
  --claude   Install or update only the Claude Code plugin adapter.
  --kimi     Prepare the Kimi Code plugin and print its in-app trust commands.
  --test     Send test notifications after installing selected adapters.
  --install-deps  Install terminal-notifier with Homebrew when missing.
  --dry-run  Print planned changes without writing files or installing packages.
EOF
}

install_codex=false
install_claude=false
install_kimi=false
run_test=false
install_deps=false
dry_run=false

if [[ $# -eq 0 ]]; then
  install_codex=true
  install_claude=true
  install_kimi=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      install_codex=true
      install_claude=true
      install_kimi=true
      ;;
    --codex)
      install_codex=true
      ;;
    --claude|--claude-code)
      install_claude=true
      ;;
    --kimi|--kimi-code)
      install_kimi=true
      ;;
    --test)
      run_test=true
      ;;
    --install-deps)
      install_deps=true
      ;;
    --no-brew)
      install_deps=false
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

find_kimi() {
  if command -v kimi >/dev/null 2>&1; then
    command -v kimi
    return 0
  fi
  if [[ -x "$HOME/.kimi-code/bin/kimi" ]]; then
    printf '%s\n' "$HOME/.kimi-code/bin/kimi"
    return 0
  fi
  return 1
}

install_manager() {
  if [[ "$dry_run" == true ]]; then
    echo "Would install management CLI: $MANAGE_CLI"
    echo "Would install report CLI: $REPORT_CLI"
    [[ "$install_claude" == true ]] && echo "Would install the Claude runtime adapter into: $APP_DATA_DIR/bin"
    [[ "$install_kimi" == true ]] && echo "Would install the Kimi runtime adapter into: $APP_DATA_DIR/bin"
    return 0
  fi
  /bin/mkdir -p "$BIN_DIR" "$APP_DATA_DIR/bin"
  /bin/chmod 700 "$BIN_DIR" "$APP_DATA_DIR" "$APP_DATA_DIR/bin" 2>/dev/null || true
  /bin/cp "$SCRIPT_DIR/ai-session-notifier" "$MANAGE_CLI"
  /bin/cp "$SCRIPT_DIR/ai-session-notifier" "$APP_DATA_DIR/bin/ai-session-notifier"
  /bin/cp "$SCRIPT_DIR/ai-session-report" "$REPORT_CLI"
  /bin/cp "$SCRIPT_DIR/ai-session-report" "$APP_DATA_DIR/bin/ai-session-report"
  /bin/chmod 700 "$MANAGE_CLI" "$REPORT_CLI" "$APP_DATA_DIR/bin/ai-session-notifier" "$APP_DATA_DIR/bin/ai-session-report"
  if [[ "$install_claude" == true ]]; then
    /bin/cp "$TOOL_DIR/claude-code-plugin/bin/ai-session-notify" "$APP_DATA_DIR/bin/ai-session-notify"
    /bin/cp "$TOOL_DIR/claude-code-plugin/bin/ai-session-notify.ps1" "$APP_DATA_DIR/bin/ai-session-notify.ps1"
    /bin/cp "$TOOL_DIR/claude-code-plugin/bin/ai-session-notify.cmd" "$APP_DATA_DIR/bin/ai-session-notify.cmd"
    /bin/chmod 700 "$APP_DATA_DIR/bin/ai-session-notify"
    /bin/chmod 600 "$APP_DATA_DIR/bin/ai-session-notify.ps1" "$APP_DATA_DIR/bin/ai-session-notify.cmd"
  fi
  if [[ "$install_kimi" == true ]]; then
    /bin/cp "$TOOL_DIR/kimi-code-plugin/hooks/ai-session-notify" "$APP_DATA_DIR/bin/kimi-session-notify"
    /bin/cp "$TOOL_DIR/kimi-code-plugin/hooks/ai-session-notify.ps1" "$APP_DATA_DIR/bin/kimi-session-notify.ps1"
    /bin/chmod 700 "$APP_DATA_DIR/bin/kimi-session-notify"
    /bin/chmod 600 "$APP_DATA_DIR/bin/kimi-session-notify.ps1"
  fi
  "$MANAGE_CLI" init >/dev/null
}

if [[ "$install_codex" != true && "$install_claude" != true && "$install_kimi" != true ]]; then
  install_codex=true
  install_claude=true
  install_kimi=true
fi

if [[ "$install_kimi" == true ]]; then
  if kimi_bin="$(find_kimi)"; then
    kimi_version="$($kimi_bin --version 2>/dev/null || printf unknown)"
    echo "Kimi Code detected: $kimi_version (plugin hooks require 0.20.1 or newer)"
  else
    echo "Kimi Code CLI not found; install version 0.20.1 or newer before enabling its plugin." >&2
  fi
  echo "Kimi Code requires interactive third-party plugin trust. Run inside Kimi Code:"
  echo "/plugins install $TOOL_DIR/kimi-code-plugin"
  echo "/plugins enable ai-session-notifier"
  echo "/reload"
  if [[ "$run_test" == true && "$dry_run" != true ]]; then
    printf '%s\n' '{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"ai-session-notifier-test","cwd":"'"$TOOL_DIR"'"}' \
      | "$TOOL_DIR/kimi-code-plugin/hooks/ai-session-notify"
    echo "Sent Kimi Code adapter test notification. This verifies the adapter, not Kimi's plugin registry."
  fi
fi

install_manager

if [[ "$install_codex" == true ]]; then
  codex_args=(--skip-cli)
  [[ "$run_test" == true ]] && codex_args+=(--test)
  [[ "$install_deps" == true ]] && codex_args+=(--install-deps)
  [[ "$dry_run" == true ]] && codex_args+=(--dry-run)
  "$TOOL_DIR/codex-plugin/scripts/install.sh" "${codex_args[@]}"
fi

if [[ "$install_claude" == true ]]; then
  if ! claude_bin="$(find_claude)"; then
    echo "Claude Code CLI not found; skipped Claude Code adapter." >&2
  elif [[ "$dry_run" == true ]]; then
    echo "Would add/update Claude Code plugin ai-session-notifier@dylon-tiny-kits using: $claude_bin"
  else
    claude_dir="$(cd -- "$(dirname -- "$claude_bin")" && pwd)"
    PATH="$claude_dir:$PATH" "$claude_bin" plugin marketplace add "$REPO_ROOT" >/dev/null 2>&1 || true
    if PATH="$claude_dir:$PATH" "$claude_bin" plugin list 2>/dev/null | grep -q 'ai-session-notifier@dylon-tiny-kits'; then
      PATH="$claude_dir:$PATH" "$claude_bin" plugin update ai-session-notifier@dylon-tiny-kits --scope user \
        || PATH="$claude_dir:$PATH" "$claude_bin" plugin install ai-session-notifier@dylon-tiny-kits --scope user
    else
      PATH="$claude_dir:$PATH" "$claude_bin" plugin install ai-session-notifier@dylon-tiny-kits --scope user
    fi

    if [[ "$run_test" == true ]]; then
      printf '%s\n' '{"hook_event_name":"Notification","notification_type":"idle_prompt","cwd":"'"$TOOL_DIR"'"}' \
        | "$TOOL_DIR/claude-code-plugin/bin/ai-session-notify"
      echo "Sent Claude Code adapter test notification."
    fi
  fi
fi

if [[ "$dry_run" == true ]]; then
  echo "AI Session Notifier dry run complete; no files changed."
  exit 0
fi

echo "AI Session Notifier install complete."
echo "Config: ${AI_SESSION_NOTIFIER_CONFIG:-$APP_CONFIG_DIR/config.json}"
echo "Ledger: ${AI_SESSION_NOTIFIER_EVENTS_FILE:-$APP_DATA_DIR/events.jsonl}"
echo "Manager: $MANAGE_CLI"
echo "Report: $REPORT_CLI"
"$MANAGE_CLI" doctor || true
