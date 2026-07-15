#!/bin/zsh
set -u
umask 077

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOK_DIR="$CODEX_HOME/hooks"
LOG_FILE="$HOOK_DIR/codex-notify.log"
APP_CONFIG_DIR="${AI_SESSION_NOTIFIER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-session-notifier}"
APP_DATA_DIR="${AI_SESSION_NOTIFIER_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-session-notifier}"
APP_CONFIG_FILE="${AI_SESSION_NOTIFIER_CONFIG:-$APP_CONFIG_DIR/config.json}"
APP_EVENTS_FILE="${AI_SESSION_NOTIFIER_EVENTS_FILE:-$APP_DATA_DIR/events.jsonl}"
APP_SESSIONS_FILE="${AI_SESSION_NOTIFIER_SESSIONS_FILE:-$APP_DATA_DIR/sessions.json}"
APP_STATE_DIR="$APP_DATA_DIR/state"
APP_DEBUG_DIR="$APP_DATA_DIR/debug"
APP_DEBUG_PAYLOAD_FILE="$APP_DEBUG_DIR/last-payload.json"

/bin/mkdir -p "$HOOK_DIR" >/dev/null 2>&1 || true
/bin/chmod 700 "$HOOK_DIR" >/dev/null 2>&1 || true

open_target_from_cli() {
  local target_url="${1:-}"
  local bundle_id="${2:-}"
  local cwd_path="${3:-}"
  local open_workspace="${4:-true}"
  local focus_vscode="${5:-true}"

  /usr/bin/osascript - "$target_url" "$bundle_id" "$cwd_path" "$open_workspace" "$focus_vscode" <<'OSA' >/dev/null 2>&1 || true
on run argv
  set targetUrl to item 1 of argv
  set bundleId to item 2 of argv
  set cwdPath to item 3 of argv
  set openWorkspaceFirst to item 4 of argv
  set focusVSCodeWindow to item 5 of argv

  my openTarget(targetUrl, bundleId, cwdPath, openWorkspaceFirst, focusVSCodeWindow)
end run

on openTarget(targetUrl, bundleId, cwdPath, openWorkspaceFirst, focusVSCodeWindow)
  try
    if bundleId is "com.microsoft.VSCode" and cwdPath is not "" and cwdPath is not "unknown" then
      if focusVSCodeWindow is not "false" then
        my focusVSCodeWindowByPath(cwdPath)
        delay 0.12
      end if
      if openWorkspaceFirst is not "false" then
        do shell script "open -b " & quoted form of bundleId & " " & quoted form of cwdPath
        delay 0.35
      end if
      if focusVSCodeWindow is not "false" then
        my focusVSCodeWindowByPath(cwdPath)
        delay 0.12
      end if
    end if
  end try

  if targetUrl is not "" then
    do shell script "open " & quoted form of targetUrl
    if bundleId is "com.microsoft.VSCode" and cwdPath is not "" and cwdPath is not "unknown" and focusVSCodeWindow is not "false" then
      delay 0.35
      my focusVSCodeWindowByPath(cwdPath)
    end if
  else if bundleId is not "" then
    do shell script "open -b " & quoted form of bundleId
  end if
end openTarget

on focusVSCodeWindowByPath(cwdPath)
  set workspaceName to ""
  set parentName to ""
  try
    set workspaceName to do shell script "/usr/bin/basename " & quoted form of cwdPath
  end try
  try
    set parentPath to do shell script "/usr/bin/dirname " & quoted form of cwdPath
    set parentName to do shell script "/usr/bin/basename " & quoted form of parentPath
  end try

  try
    tell application id "com.microsoft.VSCode" to activate
  end try
  delay 0.1

  try
    tell application "System Events"
      set codeProcesses to (application processes whose bundle identifier is "com.microsoft.VSCode")
      if (count of codeProcesses) is 0 then
        set codeProcesses to (application processes whose name is "Code")
      end if
      repeat with codeProcess in codeProcesses
        set frontmost of codeProcess to true
        repeat with candidateWindow in windows of codeProcess
          set windowTitle to ""
          try
            set windowTitle to name of candidateWindow as text
          end try
          if my titleMatches(windowTitle, cwdPath, workspaceName, parentName) then
            try
              perform action "AXRaise" of candidateWindow
            end try
            try
              set value of attribute "AXMain" of candidateWindow to true
            end try
            return true
          end if
        end repeat
      end repeat
    end tell
  end try
  return false
end focusVSCodeWindowByPath

on titleMatches(windowTitle, cwdPath, workspaceName, parentName)
  if windowTitle is "" then return false
  if cwdPath is not "" and windowTitle contains cwdPath then return true
  if workspaceName is not "" and windowTitle contains workspaceName then return true
  if parentName is not "" and windowTitle contains parentName then return true
  return false
end titleMatches
OSA
}

if [[ "${1:-}" == "--open-target" ]]; then
  shift
  open_target_from_cli "$@"
  exit 0
fi

input="$(cat 2>/dev/null || true)"
event="${1:-}"

extract_json_value() {
  local keys="$1"
  if [[ -z "$input" ]]; then
    return 0
  fi

  PAYLOAD="$input" KEYS="$keys" /usr/bin/perl -MJSON::PP -e '
    my $payload = $ENV{PAYLOAD} // "";
    my @keys = split /,/, ($ENV{KEYS} // "");
    my $data = eval { decode_json($payload) };
    exit 0 if $@ || !defined $data;

    sub scalar_value {
      my ($value) = @_;
      return undef if ref($value);
      return undef if !defined($value);
      return "$value";
    }

    sub walk {
      my ($node) = @_;
      if (ref($node) eq "HASH") {
        for my $key (@keys) {
          if (exists $node->{$key}) {
            my $value = scalar_value($node->{$key});
            if (defined $value && length $value) {
              print $value;
              exit 0;
            }
          }
        }
        for my $container_key ("thread", "session", "turn") {
          if (ref($node->{$container_key}) eq "HASH" && exists $node->{$container_key}->{id}) {
            my $value = scalar_value($node->{$container_key}->{id});
            if (defined $value && length $value) {
              print $value;
              exit 0;
            }
          }
        }
        for my $value (values %$node) {
          walk($value);
        }
      } elsif (ref($node) eq "ARRAY") {
        for my $value (@$node) {
          walk($value);
        }
      }
    }

    walk($data);
  ' 2>/dev/null || true
}

url_escape() {
  /usr/bin/perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$1" 2>/dev/null || printf '%s' "$1"
}

shell_quote_args() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("${(qq)arg}")
  done
  printf '%s' "${(j: :)quoted}"
}

ensure_app_state() {
  /bin/mkdir -p "$APP_CONFIG_DIR" "$APP_DATA_DIR" "$APP_STATE_DIR" >/dev/null 2>&1 || true
  /bin/chmod 700 "$APP_CONFIG_DIR" "$APP_DATA_DIR" "$APP_STATE_DIR" >/dev/null 2>&1 || true
  if [[ ! -f "$APP_CONFIG_FILE" ]]; then
    /bin/cat > "$APP_CONFIG_FILE" <<'JSON' 2>/dev/null || true
{
  "version": 2,
  "notifications": {
    "enabled": true,
    "dialogs": true,
    "sound": true,
    "ignoreDnD": true,
    "iconPath": "",
    "codexIconPath": "",
    "claudeIconPath": ""
  },
  "noise": {
    "dedupeSeconds": 20,
    "observationMode": "notify"
  },
  "ledger": {
    "enabled": true,
    "includeMessageExcerpt": false,
    "maxMessageChars": 260,
    "retentionDays": 30,
    "maxBytes": 5242880
  },
  "routing": {
    "openWorkspaceFirst": true,
    "focusVSCodeWindow": true
  },
  "debug": {
    "saveRawPayload": false,
    "logEnabled": false
  }
}
JSON
  fi
  /bin/chmod 600 "$APP_CONFIG_FILE" >/dev/null 2>&1 || true
  /bin/chmod 600 "$APP_EVENTS_FILE" "$APP_SESSIONS_FILE" "$LOG_FILE" >/dev/null 2>&1 || true
}

config_get() {
  local key="$1"
  local default_value="${2:-}"
  if [[ ! -f "$APP_CONFIG_FILE" ]]; then
    printf '%s' "$default_value"
    return 0
  fi

  CONFIG_FILE="$APP_CONFIG_FILE" CONFIG_KEY="$key" CONFIG_DEFAULT="$default_value" /usr/bin/perl -MJSON::PP -e '
    my $file = $ENV{CONFIG_FILE};
    my $key = $ENV{CONFIG_KEY} // "";
    my $default = $ENV{CONFIG_DEFAULT} // "";
    local $/;
    open my $fh, "<", $file or do { print $default; exit 0 };
    my $text = <$fh>;
    close $fh;
    my $data = eval { decode_json($text) };
    if ($@ || ref($data) ne "HASH") { print $default; exit 0 }
    my $node = $data;
    for my $part (split /\./, $key) {
      if (ref($node) eq "HASH" && exists $node->{$part}) {
        $node = $node->{$part};
      } else {
        print $default;
        exit 0;
      }
    }
    if (!ref($node)) {
      print $node;
    } elsif (ref($node) eq "JSON::PP::Boolean") {
      print $node ? "true" : "false";
    } else {
      print $default;
    }
  ' 2>/dev/null || printf '%s' "$default_value"
}

flag_enabled() {
  local value
  value="$(printf '%s' "${1:-}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "true" || "$value" == "1" || "$value" == "yes" || "$value" == "on" ]]
}

hash_key() {
  local hash
  hash="$(printf '%s' "$1" | /usr/bin/perl -MDigest::MD5=md5_hex -0e 'local $/; print md5_hex(<STDIN>);' 2>/dev/null || true)"
  if [[ -z "$hash" ]]; then
    hash="$(printf '%s' "$1" | /usr/bin/cksum | /usr/bin/awk '{print $1}' 2>/dev/null || true)"
  fi
  printf '%s' "${hash:-global}"
}

apply_dedupe() {
  local seconds="$1"
  local key="$2"
  if [[ "$seconds" != <-> || "$seconds" -le 0 ]]; then
    return 0
  fi

  local state_file now last age
  state_file="$APP_STATE_DIR/$(hash_key "$key").last"
  now="$(/bin/date '+%s')"
  last=""
  if [[ -f "$state_file" ]]; then
    last="$(/bin/cat "$state_file" 2>/dev/null || true)"
  fi
  if [[ "$last" == <-> ]]; then
    age=$((now - last))
    if [[ "$age" -ge 0 && "$age" -lt "$seconds" ]]; then
      suppressed="true"
      suppression_reason="dedupe:${age}s"
      return 0
    fi
  fi
  printf '%s' "$now" > "$state_file" 2>/dev/null || true
}

write_shared_ledger() {
  if ! flag_enabled "$ledger_enabled"; then
    return 0
  fi

  AS_EVENTS_FILE="$APP_EVENTS_FILE" \
  AS_SESSIONS_FILE="$APP_SESSIONS_FILE" \
  AS_TIMESTAMP="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  AS_TOOL="Codex" \
  AS_EVENT="${event:-unknown}" \
  AS_NOTIFICATION_TYPE="" \
  AS_CATEGORY="$category" \
  AS_THREAD_ID="${thread_id:-}" \
  AS_SOURCE="${source_name:-}" \
  AS_CWD="${cwd:-}" \
  AS_TARGET_URL="${open_url:-}" \
  AS_TITLE="$title" \
  AS_MESSAGE="$message" \
  AS_LAST_MESSAGE="${last_message:-}" \
  AS_SUPPRESSED="$suppressed" \
  AS_SUPPRESSION_REASON="$suppression_reason" \
  AS_MAX_MESSAGE_CHARS="$max_message_chars" \
  AS_INCLUDE_MESSAGE_EXCERPT="$include_message_excerpt" \
  /usr/bin/perl -MJSON::PP -MEncode=decode -e '
    use Fcntl qw(:flock SEEK_SET);
    sub env_text {
      my ($key) = @_;
      return decode("UTF-8", $ENV{$key} // "", 1);
    }
    my $max = int($ENV{AS_MAX_MESSAGE_CHARS} || 260);
    $max = 260 if $max <= 0;
    my $last = (($ENV{AS_INCLUDE_MESSAGE_EXCERPT} // "") eq "true")
      ? env_text("AS_LAST_MESSAGE") : "";
    if (length($last) > $max) {
      $last = substr($last, 0, $max - 3) . "...";
    }
    my $entry = {
      schemaVersion => 1,
      timestamp => env_text("AS_TIMESTAMP"),
      tool => env_text("AS_TOOL"),
      event => env_text("AS_EVENT"),
      notificationType => env_text("AS_NOTIFICATION_TYPE"),
      category => env_text("AS_CATEGORY"),
      threadId => env_text("AS_THREAD_ID"),
      source => env_text("AS_SOURCE"),
      cwd => env_text("AS_CWD"),
      targetUrl => env_text("AS_TARGET_URL"),
      title => env_text("AS_TITLE"),
      message => env_text("AS_MESSAGE"),
      lastAssistantMessage => $last,
      suppressed => (($ENV{AS_SUPPRESSED} // "") eq "true" ? JSON::PP::true : JSON::PP::false),
      suppressionReason => env_text("AS_SUPPRESSION_REASON"),
    };
    my $json = JSON::PP->new->canonical->ascii(0);
    my $events_file = $ENV{AS_EVENTS_FILE};
    if (defined $events_file && length $events_file) {
      open my $events, ">>", $events_file;
      if ($events) {
        flock($events, LOCK_EX);
        binmode $events, ":encoding(UTF-8)";
        print {$events} $json->encode($entry), "\n";
        close $events;
      }
    }

    my $sessions_file = $ENV{AS_SESSIONS_FILE};
    my $identity = $entry->{threadId} || $entry->{cwd};
    if (defined $sessions_file && length $sessions_file && length $identity) {
      open my $sessions, "+>>", $sessions_file;
      if ($sessions) {
        flock($sessions, LOCK_EX);
        seek($sessions, 0, SEEK_SET);
        local $/;
        my $text = <$sessions> // "";
        my $registry = eval { decode_json($text) };
        $registry = {} if $@ || ref($registry) ne "HASH";
        $registry->{version} = 1;
        $registry->{sessions} = {} if ref($registry->{sessions}) ne "HASH";
        my $tool = lc($entry->{tool});
        $tool =~ s/\s+/-/g;
        my $key = $tool . ":" . $identity;
        $registry->{sessions}{$key} = $entry;
        $registry->{updatedAt} = $entry->{timestamp};
        seek($sessions, 0, SEEK_SET);
        truncate($sessions, 0);
        binmode $sessions, ":encoding(UTF-8)";
        print {$sessions} JSON::PP->new->canonical->ascii(0)->pretty->encode($registry);
        close $sessions;
      }
    }
  ' 2>/dev/null || true
}

cleanup_storage_if_due() {
  local now last age retention_days max_bytes cutoff
  now="$(/bin/date '+%s')"
  last="$(/bin/cat "$APP_STATE_DIR/cleanup.last" 2>/dev/null || true)"
  if [[ "$last" == <-> ]]; then
    age=$((now - last))
    [[ "$age" -ge 0 && "$age" -lt 86400 ]] && return 0
  fi

  retention_days="$(config_get "ledger.retentionDays" "30")"
  max_bytes="$(config_get "ledger.maxBytes" "5242880")"
  [[ "$retention_days" == <-> ]] || retention_days="30"
  [[ "$max_bytes" == <-> ]] || max_bytes="5242880"
  cutoff="$(/bin/date -u -v-"${retention_days}"d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"

  AS_EVENTS_FILE="$APP_EVENTS_FILE" \
  AS_SESSIONS_FILE="$APP_SESSIONS_FILE" \
  AS_CUTOFF="$cutoff" \
  AS_MAX_BYTES="$max_bytes" \
  /usr/bin/perl -MJSON::PP -e '
    use Fcntl qw(:flock SEEK_SET);
    my $cutoff = $ENV{AS_CUTOFF} // "";
    my $max = int($ENV{AS_MAX_BYTES} || 0);

    my $events_file = $ENV{AS_EVENTS_FILE};
    if (defined $events_file && -f $events_file && open my $events, "+<", $events_file) {
      flock($events, LOCK_EX);
      my @kept;
      while (my $line = <$events>) {
        my $entry = eval { decode_json($line) };
        next if $@ || ref($entry) ne "HASH";
        my $timestamp = $entry->{timestamp} // "";
        push @kept, $line if !length($cutoff) || !length($timestamp) || $timestamp ge $cutoff;
      }
      if ($max > 0) {
        my $bytes = 0;
        my @bounded;
        for my $line (reverse @kept) {
          my $size = length($line);
          last if @bounded && $bytes + $size > $max;
          unshift @bounded, $line;
          $bytes += $size;
        }
        @kept = @bounded;
      }
      seek($events, 0, SEEK_SET);
      truncate($events, 0);
      print {$events} @kept;
      close $events;
    }

    my $sessions_file = $ENV{AS_SESSIONS_FILE};
    if (defined $sessions_file && -f $sessions_file && open my $sessions, "+<", $sessions_file) {
      flock($sessions, LOCK_EX);
      local $/;
      my $text = <$sessions> // "";
      my $registry = eval { decode_json($text) };
      if (!$@ && ref($registry) eq "HASH" && ref($registry->{sessions}) eq "HASH") {
        for my $key (keys %{$registry->{sessions}}) {
          my $entry = $registry->{sessions}{$key};
          my $timestamp = ref($entry) eq "HASH" ? ($entry->{timestamp} // "") : "";
          delete $registry->{sessions}{$key}
            if length($cutoff) && length($timestamp) && $timestamp lt $cutoff;
        }
        seek($sessions, 0, SEEK_SET);
        truncate($sessions, 0);
        print {$sessions} JSON::PP->new->canonical->ascii(0)->pretty->encode($registry);
      }
      close $sessions;
    }
  ' 2>/dev/null || true

  /usr/bin/printf '%s' "$now" > "$APP_STATE_DIR/cleanup.last" 2>/dev/null || true
}

ensure_app_state

if [[ -z "$event" && -n "${CODEX_HOOK_EVENT_NAME:-}" ]]; then
  event="$CODEX_HOOK_EVENT_NAME"
fi

if [[ -z "$event" && -n "$input" ]]; then
  event="$(extract_json_value "hook_event_name,event_name,eventName")"
fi

thread_id="$(extract_json_value "thread_id,threadId,session_id,sessionId,conversation_id,conversationId")"
source_name="$(extract_json_value "originator,app,client,source,thread_source,threadSource")"
cwd="$(extract_json_value "cwd,current_working_directory,working_directory,workingDirectory")"
last_message="$(extract_json_value "last_assistant_message,lastAssistantMessage")"
lower_last_message="$(printf '%s' "$last_message" | /usr/bin/tr '[:upper:]' '[:lower:]')"

save_raw_payload="$(config_get "debug.saveRawPayload" "false")"
if [[ -n "$input" ]] && flag_enabled "$save_raw_payload"; then
  /bin/mkdir -p "$APP_DEBUG_DIR" >/dev/null 2>&1 || true
  /bin/chmod 700 "$APP_DEBUG_DIR" >/dev/null 2>&1 || true
  /usr/bin/printf '%s\n' "$input" > "$APP_DEBUG_PAYLOAD_FILE" 2>/dev/null || true
  /bin/chmod 600 "$APP_DEBUG_PAYLOAD_FILE" >/dev/null 2>&1 || true
fi

if [[ -n "$thread_id" && -z "$source_name" && -d "$CODEX_HOME/sessions" ]]; then
  rollout_path="$(/usr/bin/find "$CODEX_HOME/sessions" -name "*${thread_id}.jsonl" -print -quit 2>/dev/null)"
  if [[ -n "$rollout_path" ]]; then
    first_line="$(/usr/bin/head -n 1 "$rollout_path" 2>/dev/null || true)"
    source_name="$(PAYLOAD="$first_line" KEYS="originator,app,client,source,thread_source,threadSource" /usr/bin/perl -MJSON::PP -e '
      my $data = eval { decode_json($ENV{PAYLOAD} // "") };
      exit 0 if $@ || ref($data) ne "HASH";
      my $payload = $data->{payload};
      exit 0 if ref($payload) ne "HASH";
      for my $key (split /,/, ($ENV{KEYS} // "")) {
        my $value = $payload->{$key};
        if (defined $value && !ref($value) && length "$value") {
          print $value;
          exit 0;
        }
      }
    ' 2>/dev/null || true)"
    if [[ -z "$cwd" ]]; then
      cwd="$(PAYLOAD="$first_line" /usr/bin/perl -MJSON::PP -e '
        my $data = eval { decode_json($ENV{PAYLOAD} // "") };
        exit 0 if $@ || ref($data) ne "HASH";
        my $payload = $data->{payload};
        exit 0 if ref($payload) ne "HASH";
        my $value = $payload->{cwd};
        print $value if defined $value && !ref($value);
      ' 2>/dev/null || true)"
    fi
  fi
fi

category="attention"
observation_event="false"

case "$event" in
  Stop|stop)
    category="turn_stop"
    title="Codex 本轮已停下"
    message="本轮回复/工具执行已经结束，可能是在等待你或等待后续观察窗口。"
    if [[ "$lower_last_message" == *"观察"* || "$lower_last_message" == *"观察窗口"* || "$lower_last_message" == *"继续观察"* || "$lower_last_message" == *"monitor"* || "$lower_last_message" == *"watch"* || "$lower_last_message" == *"稍后"* || "$lower_last_message" == *"分钟"* || "$lower_last_message" == *"有异常"* || "$lower_last_message" == *"加载中"* ]]; then
      category="observation"
      observation_event="true"
      title="Codex 已进入观察窗口"
      message="本轮已暂时停下，但任务可能还在观察/等待后续检查，并不代表最终完成。"
    fi
    sound_file="/System/Library/Sounds/Glass.aiff"
    sound_name="Glass"
    ;;
  PermissionRequest|permission|approval)
    category="permission"
    title="Codex 正在等你确认权限"
    message="需要在 Codex 或 VS Code 里批准/拒绝权限请求。"
    sound_file="/System/Library/Sounds/Hero.aiff"
    sound_name="Hero"
    ;;
  *)
    title="Codex 提醒"
    message="Codex 有状态需要你查看。"
    sound_file="/System/Library/Sounds/Glass.aiff"
    sound_name="Glass"
    ;;
esac

open_url=""
fallback_url=""
activate_bundle="com.openai.codex"
fallback_bundle=""
primary_button="打开会话"
fallback_button=""
lower_source="$(printf '%s' "$source_name" | /usr/bin/tr '[:upper:]' '[:lower:]')"
open_workspace_first="$(config_get "routing.openWorkspaceFirst" "true")"
focus_vscode_window="$(config_get "routing.focusVSCodeWindow" "true")"

if [[ -n "$thread_id" ]]; then
  vscode_url="vscode://openai.chatgpt/local/$(url_escape "$thread_id")"
  codex_url="codex://threads/$(url_escape "$thread_id")"
  if [[ "$lower_source" == *"vscode"* || "$lower_source" == *"vs code"* ]]; then
    open_url="$vscode_url"
    fallback_url="$codex_url"
    activate_bundle="com.microsoft.VSCode"
    fallback_bundle="com.openai.codex"
  else
    open_url="$codex_url"
    fallback_url="$vscode_url"
    activate_bundle="com.openai.codex"
    fallback_bundle="com.microsoft.VSCode"
  fi
  primary_button="打开会话"
elif [[ "$lower_source" == *"vscode"* || "$lower_source" == *"vs code"* ]]; then
  open_url="vscode://openai.chatgpt/"
  activate_bundle="com.microsoft.VSCode"
  primary_button="打开会话"
fi

icon_path="$(config_get "notifications.codexIconPath" "")"
if [[ -z "$icon_path" || ! -f "$icon_path" ]]; then
  icon_path="$(config_get "notifications.iconPath" "")"
fi
if [[ -z "$icon_path" || ! -f "$icon_path" ]]; then
  icon_path=""
  for candidate in \
    /Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png \
    /Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png" \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png" \
    /Applications/Codex.app/Contents/Resources/icon.png \
    /Applications/Codex.app/Contents/Resources/icon.icns \
    /Applications/Codex.app/Contents/Resources/app.icns \
    "$HOME/Applications/Codex.app/Contents/Resources/icon.png" \
    "$HOME/Applications/Codex.app/Contents/Resources/icon.icns" \
    "$HOME/Applications/Codex.app/Contents/Resources/app.icns"; do
    if [[ -f "$candidate" ]]; then
      icon_path="$candidate"
      break
    fi
  done
fi
if [[ -z "$icon_path" ]]; then
  for extension_root in "$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" "$HOME/.cursor/extensions"; do
    [[ -d "$extension_root" ]] || continue
    candidate="$(/usr/bin/find "$extension_root" -maxdepth 4 -type f -path '*/openai.chatgpt-*/webview/assets/codex-app-ga-logo--*.png' -print 2>/dev/null | /usr/bin/sort | /usr/bin/tail -n 1)"
    if [[ -f "$candidate" ]]; then
      icon_path="$candidate"
      break
    fi
  done
fi

timestamp="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
notifications_enabled="$(config_get "notifications.enabled" "true")"
dialogs_enabled="$(config_get "notifications.dialogs" "true")"
sound_enabled="$(config_get "notifications.sound" "true")"
ignore_dnd_enabled="$(config_get "notifications.ignoreDnD" "true")"
dedupe_seconds="$(config_get "noise.dedupeSeconds" "20")"
observation_mode="$(config_get "noise.observationMode" "notify")"
ledger_enabled="$(config_get "ledger.enabled" "true")"
include_message_excerpt="$(config_get "ledger.includeMessageExcerpt" "false")"
max_message_chars="$(config_get "ledger.maxMessageChars" "260")"
debug_log_enabled="$(config_get "debug.logEnabled" "false")"
suppressed="false"
suppression_reason=""

if ! flag_enabled "$notifications_enabled"; then
  suppressed="true"
  suppression_reason="notifications_disabled"
elif [[ "$observation_event" == "true" && "$observation_mode" == "quiet" ]]; then
  suppressed="true"
  suppression_reason="observation_quiet"
fi

if [[ "$suppressed" != "true" ]]; then
  apply_dedupe "$dedupe_seconds" "codex|${event:-unknown}|${category:-unknown}|${thread_id:-unknown}|${cwd:-unknown}|${source_name:-unknown}"
fi

write_shared_ledger
cleanup_storage_if_due

if flag_enabled "$debug_log_enabled"; then
  /usr/bin/printf '[%s] %s category=%s suppressed=%s thread=%s source=%s cwd=%s target=%s\n' "$timestamp" "${event:-unknown}" "${category:-unknown}" "$suppressed" "${thread_id:-unknown}" "${source_name:-unknown}" "${cwd:-unknown}" "${open_url:-activate:$activate_bundle}" >> "$LOG_FILE" 2>/dev/null || true
  /bin/chmod 600 "$LOG_FILE" >/dev/null 2>&1 || true
fi

if [[ "$suppressed" == "true" ]]; then
  exit 0
fi

if flag_enabled "${AI_SESSION_NOTIFIER_DRY_RUN:-false}"; then
  exit 0
fi

terminal_notifier="$(command -v terminal-notifier 2>/dev/null || true)"
if [[ -z "$terminal_notifier" && -x /opt/homebrew/bin/terminal-notifier ]]; then
  terminal_notifier="/opt/homebrew/bin/terminal-notifier"
elif [[ -z "$terminal_notifier" && -x /usr/local/bin/terminal-notifier ]]; then
  terminal_notifier="/usr/local/bin/terminal-notifier"
fi

if [[ -n "$terminal_notifier" && -x "$terminal_notifier" ]]; then
  notifier_args=(
    -title "$title"
    -message "$message"
    -group "codex-${thread_id:-global}-${event:-event}"
  )

  if flag_enabled "$sound_enabled"; then
    notifier_args+=(-sound "$sound_name")
  fi

  if flag_enabled "$ignore_dnd_enabled"; then
    notifier_args+=(-ignoreDnD)
  fi

  if [[ -n "$icon_path" ]]; then
    notifier_args+=(-appIcon "$icon_path")
  fi

  if [[ -n "$open_url" ]]; then
    if [[ "$activate_bundle" == "com.microsoft.VSCode" ]]; then
      execute_command="$(shell_quote_args "$0" "--open-target" "$open_url" "$activate_bundle" "$cwd" "$open_workspace_first" "$focus_vscode_window")"
      if [[ -n "$execute_command" ]]; then
        notifier_args+=(-execute "$execute_command")
      else
        notifier_args+=(-open "$open_url")
      fi
    else
      notifier_args+=(-open "$open_url")
    fi
  else
    notifier_args+=(-activate "$activate_bundle")
  fi

  "$terminal_notifier" "${notifier_args[@]}" >/dev/null 2>&1 || true
else
  if flag_enabled "$sound_enabled"; then
    /usr/bin/osascript - "$title" "$message" "$sound_name" <<'OSA' >/dev/null 2>&1 || true
on run argv
  set notificationTitle to item 1 of argv
  set notificationMessage to item 2 of argv
  set notificationSound to item 3 of argv
  display notification notificationMessage with title notificationTitle sound name notificationSound
end run
OSA
  else
    /usr/bin/osascript - "$title" "$message" <<'OSA' >/dev/null 2>&1 || true
on run argv
  set notificationTitle to item 1 of argv
  set notificationMessage to item 2 of argv
  display notification notificationMessage with title notificationTitle
end run
OSA
  fi
fi

if ! flag_enabled "$dialogs_enabled"; then
  if [[ -f "$sound_file" ]] && flag_enabled "$sound_enabled"; then
    /usr/bin/afplay "$sound_file" >/dev/null 2>&1 &
  fi
  exit 0
fi

alert_timeout="8"
if [[ "$event" == PermissionRequest || "$event" == permission || "$event" == approval ]]; then
  alert_timeout="30"
fi

/usr/bin/osascript - "$title" "$message" "$alert_timeout" "$icon_path" "$open_url" "$activate_bundle" "$cwd" "$primary_button" "$fallback_url" "$fallback_bundle" "$fallback_button" "$open_workspace_first" "$focus_vscode_window" <<'OSA' >/dev/null 2>&1 &
on run argv
  set notificationTitle to item 1 of argv
  set notificationMessage to item 2 of argv
  set timeoutSeconds to (item 3 of argv) as integer
  set iconPath to item 4 of argv
  set targetUrl to item 5 of argv
  set activateBundle to item 6 of argv
  set cwdPath to item 7 of argv
  set primaryButton to item 8 of argv
  set fallbackUrl to item 9 of argv
  set fallbackBundle to item 10 of argv
  set fallbackButton to item 11 of argv
  set openWorkspaceFirst to item 12 of argv
  set focusVSCodeWindow to item 13 of argv

  if primaryButton is "" then set primaryButton to "打开应用"

  try
    if fallbackButton is not "" then
      set buttonList to {"知道了", fallbackButton, primaryButton}
    else
      set buttonList to {"知道了", primaryButton}
    end if

    if iconPath is not "" then
      set dialogResult to display dialog notificationMessage with title notificationTitle buttons buttonList default button primaryButton giving up after timeoutSeconds with icon POSIX file iconPath
    else
      set dialogResult to display dialog notificationMessage with title notificationTitle buttons buttonList default button primaryButton giving up after timeoutSeconds
    end if

    if gave up of dialogResult is false then
      if button returned of dialogResult is primaryButton then
        my openTarget(targetUrl, activateBundle, cwdPath, openWorkspaceFirst, focusVSCodeWindow)
      else if fallbackButton is not "" and button returned of dialogResult is fallbackButton then
        my openTarget(fallbackUrl, fallbackBundle, cwdPath, openWorkspaceFirst, focusVSCodeWindow)
      end if
    end if
  end try
end run

on openTarget(targetUrl, bundleId, cwdPath, openWorkspaceFirst, focusVSCodeWindow)
  try
    if bundleId is "com.microsoft.VSCode" and cwdPath is not "" and cwdPath is not "unknown" then
      if focusVSCodeWindow is not "false" then
        my focusVSCodeWindowByPath(cwdPath)
        delay 0.12
      end if
      if openWorkspaceFirst is not "false" then
        do shell script "open -b " & quoted form of bundleId & " " & quoted form of cwdPath
        delay 0.35
      end if
      if focusVSCodeWindow is not "false" then
        my focusVSCodeWindowByPath(cwdPath)
        delay 0.12
      end if
    end if
  end try

  if targetUrl is not "" then
    do shell script "open " & quoted form of targetUrl
    if bundleId is "com.microsoft.VSCode" and cwdPath is not "" and cwdPath is not "unknown" and focusVSCodeWindow is not "false" then
      delay 0.35
      my focusVSCodeWindowByPath(cwdPath)
    end if
  else if bundleId is not "" then
    do shell script "open -b " & quoted form of bundleId
  end if
end openTarget

on focusVSCodeWindowByPath(cwdPath)
  set workspaceName to ""
  set parentName to ""
  try
    set workspaceName to do shell script "/usr/bin/basename " & quoted form of cwdPath
  end try
  try
    set parentPath to do shell script "/usr/bin/dirname " & quoted form of cwdPath
    set parentName to do shell script "/usr/bin/basename " & quoted form of parentPath
  end try

  try
    tell application id "com.microsoft.VSCode" to activate
  end try
  delay 0.1

  try
    tell application "System Events"
      set codeProcesses to (application processes whose bundle identifier is "com.microsoft.VSCode")
      if (count of codeProcesses) is 0 then
        set codeProcesses to (application processes whose name is "Code")
      end if
      repeat with codeProcess in codeProcesses
        set frontmost of codeProcess to true
        repeat with candidateWindow in windows of codeProcess
          set windowTitle to ""
          try
            set windowTitle to name of candidateWindow as text
          end try
          if my titleMatches(windowTitle, cwdPath, workspaceName, parentName) then
            try
              perform action "AXRaise" of candidateWindow
            end try
            try
              set value of attribute "AXMain" of candidateWindow to true
            end try
            return true
          end if
        end repeat
      end repeat
    end tell
  end try
  return false
end focusVSCodeWindowByPath

on titleMatches(windowTitle, cwdPath, workspaceName, parentName)
  if windowTitle is "" then return false
  if cwdPath is not "" and windowTitle contains cwdPath then return true
  if workspaceName is not "" and windowTitle contains workspaceName then return true
  if parentName is not "" and windowTitle contains parentName then return true
  return false
end titleMatches
OSA
disown $! 2>/dev/null || true

if [[ -f "$sound_file" ]] && flag_enabled "$sound_enabled"; then
  /usr/bin/afplay "$sound_file" >/dev/null 2>&1 &
fi

exit 0
