#!/bin/zsh
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOK_DIR="$CODEX_HOME/hooks"
HOOKS_JSON="$CODEX_HOME/hooks.json"
HOOK_SCRIPT="$HOOK_DIR/codex-notify.sh"
APP_DATA_DIR="${AI_SESSION_NOTIFIER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-session-notifier}"
BIN_DIR="${AI_SESSION_NOTIFIER_BIN_DIR:-$HOME/.local/bin}"
MANAGE_CLI_SOURCE="$SCRIPT_DIR/ai-session-notifier"
MANAGE_CLI="$BIN_DIR/ai-session-notifier"
REPORT_CLI_SOURCE="$SCRIPT_DIR/ai-session-report"
REPORT_CLI="$BIN_DIR/ai-session-report"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"

usage() {
  cat <<'EOF'
Usage: install.sh [--test] [--install-deps] [--dry-run] [--skip-cli]

Installs Codex notification hooks into ~/.codex.

Options:
  --test     Send a test notification after install.
  --install-deps  Install terminal-notifier with Homebrew when missing.
  --dry-run  Print planned changes without writing files or installing packages.
  --skip-cli  Skip shared CLI installation when called by the root installer.
EOF
}

run_test=false
install_deps=false
dry_run=false
install_cli=true

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --skip-cli)
      install_cli=false
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

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    echo /opt/homebrew/bin/brew
    return 0
  fi
  if [[ -x /usr/local/bin/brew ]]; then
    echo /usr/local/bin/brew
    return 0
  fi
  return 1
}

ensure_terminal_notifier() {
  if command -v terminal-notifier >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/terminal-notifier || -x /usr/local/bin/terminal-notifier ]]; then
    return 0
  fi
  if [[ "$install_deps" != true ]]; then
    echo "terminal-notifier is not installed; AppleScript fallback will be used."
    echo "Re-run with --install-deps to enable Notification Center click-through."
    return 0
  fi
  local brew_bin
  if ! brew_bin="$(find_brew)"; then
    echo "Homebrew not found; falling back to non-clickable osascript notifications."
    return 0
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" list terminal-notifier >/dev/null 2>&1 \
    || HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install terminal-notifier
}

install_hook_script() {
  if [[ "$dry_run" == true ]]; then
    echo "Would install private hook script: $HOOK_SCRIPT"
    if [[ "$install_cli" == true ]]; then
      echo "Would install management CLI: $MANAGE_CLI"
      echo "Would install report CLI: $REPORT_CLI"
    fi
    echo "Would remove legacy raw payload and bundled logo files from $HOOK_DIR"
    return 0
  fi
  /bin/mkdir -p "$HOOK_DIR"
  /bin/chmod 700 "$HOOK_DIR"
  /bin/cp "$SCRIPT_DIR/codex-notify.sh" "$HOOK_SCRIPT"
  /bin/chmod 700 "$HOOK_SCRIPT"
  if [[ "$install_cli" == true ]]; then
    /bin/mkdir -p "$BIN_DIR" "$APP_DATA_DIR/bin"
    /bin/chmod 700 "$BIN_DIR" "$APP_DATA_DIR" "$APP_DATA_DIR/bin" 2>/dev/null || true
    /bin/cp "$MANAGE_CLI_SOURCE" "$MANAGE_CLI"
    /bin/cp "$MANAGE_CLI_SOURCE" "$APP_DATA_DIR/bin/ai-session-notifier"
    /bin/cp "$REPORT_CLI_SOURCE" "$REPORT_CLI"
    /bin/cp "$REPORT_CLI_SOURCE" "$APP_DATA_DIR/bin/ai-session-report"
    /bin/chmod 700 "$MANAGE_CLI" "$REPORT_CLI" "$APP_DATA_DIR/bin/ai-session-notifier" "$APP_DATA_DIR/bin/ai-session-report"
  fi
  /bin/rm -f "$HOOK_DIR/last-payload.json" "$HOOK_DIR/assets/codex-logo.png"
  /bin/rmdir "$HOOK_DIR/assets" >/dev/null 2>&1 || true
  "$MANAGE_CLI" init >/dev/null
}

merge_hooks_json() {
  if [[ "$dry_run" == true ]]; then
    echo "Would merge Stop and PermissionRequest into: $HOOKS_JSON"
    return 0
  fi
  if [[ -f "$HOOKS_JSON" ]]; then
    /bin/cp "$HOOKS_JSON" "$HOOKS_JSON.bak.$STAMP"
    /bin/chmod 600 "$HOOKS_JSON.bak.$STAMP" >/dev/null 2>&1 || true
  fi

  HOOKS_JSON="$HOOKS_JSON" HOOK_SCRIPT="$HOOK_SCRIPT" /usr/bin/perl -MJSON::PP -e '
    my $path = $ENV{HOOKS_JSON};
    my $command = $ENV{HOOK_SCRIPT};
    my $json = JSON::PP->new->utf8->pretty->canonical;
    my $data = {};

    if (-f $path) {
      local $/;
      open my $fh, "<", $path or die "Failed to read $path: $!";
      my $text = <$fh>;
      close $fh;
      $data = eval { decode_json($text) };
      $data = {} if $@ || ref($data) ne "HASH";
    }

    $data->{hooks} = {} if ref($data->{hooks}) ne "HASH";

    sub contains_command {
      my ($entry, $command) = @_;
      return 0 if ref($entry) ne "HASH";
      my $hooks = $entry->{hooks};
      return 0 if ref($hooks) ne "ARRAY";
      for my $hook (@$hooks) {
        next if ref($hook) ne "HASH";
        return 1 if ($hook->{command} // "") eq $command;
      }
      return 0;
    }

    sub install_entry {
      my ($data, $event, $entry, $command) = @_;
      my $current = $data->{hooks}{$event};
      $current = [] if ref($current) ne "ARRAY";
      my @kept = grep { !contains_command($_, $command) } @$current;
      $data->{hooks}{$event} = [$entry, @kept];
    }

    my $stop = {
      hooks => [{
        type => "command",
        command => $command,
        timeout => 5,
        statusMessage => "Sending Codex turn notification",
      }],
    };

    my $permission = {
      matcher => ".*",
      hooks => [{
        type => "command",
        command => $command,
        timeout => 5,
        statusMessage => "Sending Codex approval notification",
      }],
    };

    install_entry($data, "Stop", $stop, $command);
    install_entry($data, "PermissionRequest", $permission, $command);

    my $tmp = "$path.tmp.$$";
    open my $out, ">", $tmp or die "Failed to write $tmp: $!";
    print {$out} $json->encode($data);
    close $out;
    rename $tmp, $path or die "Failed to replace $path: $!";
  '
  /bin/chmod 600 "$HOOKS_JSON" >/dev/null 2>&1 || true
}

if [[ "$dry_run" == true ]]; then
  if [[ "$install_deps" == true ]]; then
    echo "Would install terminal-notifier with Homebrew when missing."
  else
    echo "Would keep system packages unchanged."
  fi
else
  ensure_terminal_notifier
fi
install_hook_script
merge_hooks_json

if [[ "$dry_run" == true ]]; then
  echo "Dry run complete; no files changed."
  exit 0
fi

echo "Installed AI Session Notifier Codex adapter:"
echo "  hook script: $HOOK_SCRIPT"
echo "  hooks json:  $HOOKS_JSON"
if [[ "$install_cli" == true ]]; then
  echo "  management:  $MANAGE_CLI"
  echo "  report:      $REPORT_CLI"
fi
echo
echo "If Codex asks to review hooks, choose: Trust all and continue"

if [[ "$run_test" == true ]]; then
  printf '{"hook_event_name":"Stop","threadId":"test-thread","source":"vscode"}' | "$HOOK_SCRIPT"
  echo "Sent test notification."
fi
