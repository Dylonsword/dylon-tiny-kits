#!/bin/zsh
set -euo pipefail
umask 077

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOK_DIR="$CODEX_HOME/hooks"
HOOKS_JSON="$CODEX_HOME/hooks.json"
HOOK_SCRIPT="$HOOK_DIR/codex-notify.sh"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
dry_run=false

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: uninstall.sh [--dry-run]" >&2
  exit 2
fi

if [[ "$dry_run" == true ]]; then
  echo "Would remove AI Session Notifier entries from: $HOOKS_JSON"
  echo "Would remove hook runtime files from: $HOOK_DIR"
  exit 0
fi

if [[ -f "$HOOKS_JSON" ]]; then
  /bin/cp "$HOOKS_JSON" "$HOOKS_JSON.bak.$STAMP"
  /bin/chmod 600 "$HOOKS_JSON.bak.$STAMP" >/dev/null 2>&1 || true
  HOOKS_JSON="$HOOKS_JSON" HOOK_SCRIPT="$HOOK_SCRIPT" /usr/bin/perl -MJSON::PP -e '
    my $path = $ENV{HOOKS_JSON};
    my $command = $ENV{HOOK_SCRIPT};
    local $/;
    open my $fh, "<", $path or die "Failed to read $path: $!";
    my $text = <$fh>;
    close $fh;
    my $data = eval { decode_json($text) };
    exit 0 if $@ || ref($data) ne "HASH" || ref($data->{hooks}) ne "HASH";

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

    for my $event ("Stop", "PermissionRequest") {
      my $current = $data->{hooks}{$event};
      next if ref($current) ne "ARRAY";
      my @kept = grep { !contains_command($_, $command) } @$current;
      if (@kept) {
        $data->{hooks}{$event} = \@kept;
      } else {
        delete $data->{hooks}{$event};
      }
    }

    my $json = JSON::PP->new->utf8->pretty->canonical;
    my $tmp = "$path.tmp.$$";
    open my $out, ">", $tmp or die "Failed to write $tmp: $!";
    print {$out} $json->encode($data);
    close $out;
    rename $tmp, $path or die "Failed to replace $path: $!";
  '
  /bin/chmod 600 "$HOOKS_JSON" >/dev/null 2>&1 || true
fi

/bin/rm -f "$HOOK_SCRIPT" "$HOOK_DIR/last-payload.json" "$HOOK_DIR/codex-notify.log" "$HOOK_DIR/assets/codex-logo.png"
/bin/rmdir "$HOOK_DIR/assets" >/dev/null 2>&1 || true

echo "Removed Codex Notify Hooks entries from $HOOKS_JSON"
echo "Removed $HOOK_SCRIPT"
echo "Hook backups and terminal-notifier were left in place."
