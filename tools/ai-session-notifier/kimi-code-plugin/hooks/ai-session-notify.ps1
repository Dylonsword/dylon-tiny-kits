param(
  [switch]$OpenTarget,
  [string]$TargetUrl = "",
  [string]$BundleId = "",
  [string]$CwdPath = "",
  [string]$OpenWorkspaceFirst = "true",
  [string]$FocusVSCodeWindow = "true"
)

$ErrorActionPreference = "SilentlyContinue"

function Get-ConfigDir {
  if ($env:AI_SESSION_NOTIFIER_CONFIG_DIR) { return $env:AI_SESSION_NOTIFIER_CONFIG_DIR }
  if ($env:APPDATA) { return (Join-Path $env:APPDATA "ai-session-notifier") }
  return (Join-Path $HOME ".config\ai-session-notifier")
}

function Get-DataDir {
  if ($env:AI_SESSION_NOTIFIER_DATA_DIR) { return $env:AI_SESSION_NOTIFIER_DATA_DIR }
  if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA "ai-session-notifier") }
  return (Join-Path $HOME ".local\share\ai-session-notifier")
}

$ConfigDir = Get-ConfigDir
$DataDir = Get-DataDir
$ConfigFile = if ($env:AI_SESSION_NOTIFIER_CONFIG) { $env:AI_SESSION_NOTIFIER_CONFIG } else { Join-Path $ConfigDir "config.json" }
$EventsFile = if ($env:AI_SESSION_NOTIFIER_EVENTS_FILE) { $env:AI_SESSION_NOTIFIER_EVENTS_FILE } else { Join-Path $DataDir "events.jsonl" }
$SessionsFile = if ($env:AI_SESSION_NOTIFIER_SESSIONS_FILE) { $env:AI_SESSION_NOTIFIER_SESSIONS_FILE } else { Join-Path $DataDir "sessions.json" }
$StateDir = Join-Path $DataDir "state"
$Script:Config = $null

function Test-Enabled([object]$Value) {
  $text = ([string]$Value).ToLowerInvariant()
  return ($text -eq "true" -or $text -eq "1" -or $text -eq "yes" -or $text -eq "on")
}

function Ensure-AppState {
  New-Item -ItemType Directory -Force -Path $ConfigDir, $DataDir, $StateDir | Out-Null
  if (-not (Test-Path -LiteralPath $ConfigFile)) {
    $defaultConfig = @{
      version = 2
      notifications = @{
        enabled = $true
        dialogs = $true
        sound = $true
        ignoreDnD = $true
        locale = "auto"
        iconPath = ""
        codexIconPath = ""
        claudeIconPath = ""
        kimiIconPath = ""
      }
      noise = @{
        dedupeSeconds = 20
        observationMode = "notify"
      }
      ledger = @{
        enabled = $true
        includeMessageExcerpt = $false
        maxMessageChars = 260
        retentionDays = 30
        maxBytes = 5242880
      }
      routing = @{
        openWorkspaceFirst = $true
        focusVSCodeWindow = $true
      }
      debug = @{
        saveRawPayload = $false
        logEnabled = $false
      }
    }
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($ConfigFile, ($defaultConfig | ConvertTo-Json -Depth 8), $encoding)
  }
}

function Read-Config {
  if ($Script:Config -ne $null) { return $Script:Config }
  try {
    $Script:Config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    $Script:Config = [pscustomobject]@{}
  }
  return $Script:Config
}

function Get-ConfigValue([string]$Path, [object]$DefaultValue) {
  $node = Read-Config
  foreach ($part in $Path.Split(".")) {
    if ($null -eq $node) { return $DefaultValue }
    $prop = $node.PSObject.Properties | Where-Object { $_.Name -eq $part } | Select-Object -First 1
    if ($null -eq $prop) { return $DefaultValue }
    $node = $prop.Value
  }
  if ($null -eq $node) { return $DefaultValue }
  return $node
}

function ConvertTo-NotificationLocale([string]$Value) {
  $normalized = $Value.Trim().Replace("_", "-").ToLowerInvariant()
  if ($normalized -eq "zh" -or $normalized -match "^zh-(cn|hans|sg)(-|\.|@|$)") {
    return "zh-CN"
  }
  return "en"
}

function Resolve-NotificationLocale {
  $configured = if ($env:AI_SESSION_NOTIFIER_LOCALE) {
    $env:AI_SESSION_NOTIFIER_LOCALE
  } else {
    [string](Get-ConfigValue "notifications.locale" "auto")
  }
  if (-not [string]::IsNullOrWhiteSpace($configured) -and $configured.ToLowerInvariant() -ne "auto") {
    $resolved = ConvertTo-NotificationLocale -Value $configured
    return $resolved
  }
  try {
    $resolved = ConvertTo-NotificationLocale -Value ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
    return $resolved
  } catch {
    return "en"
  }
}

function Resolve-KimiIconPath {
  foreach ($configured in @(
    [string](Get-ConfigValue "notifications.kimiIconPath" ""),
    [string](Get-ConfigValue "notifications.iconPath" "")
  )) {
    if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path -LiteralPath $configured -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $configured).Path
    }
  }

  foreach ($extensionRoot in @(
    (Join-Path $HOME ".vscode\extensions"),
    (Join-Path $HOME ".vscode-insiders\extensions"),
    (Join-Path $HOME ".cursor\extensions")
  )) {
    if (-not (Test-Path -LiteralPath $extensionRoot -PathType Container)) { continue }
    foreach ($pattern in @(
      "moonshot-ai.kimi-code-*\dist\kimi-logo.png",
      "moonshot-ai.kimi-code-*\resources\kimi-icon-storefront.png"
    )) {
      $match = Get-ChildItem -Path (Join-Path $extensionRoot $pattern) -File |
        Sort-Object FullName -Descending |
        Select-Object -First 1
      if ($null -ne $match) { return $match.FullName }
    }
  }
  return ""
}

function Get-JsonValue($Object, [string[]]$Names) {
  if ($null -eq $Object) { return "" }
  foreach ($name in $Names) {
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -ne $prop -and $null -ne $prop.Value -and -not ($prop.Value -is [array]) -and -not ($prop.Value -is [hashtable])) {
      $text = [string]$prop.Value
      if ($text.Trim().Length -gt 0) { return $text }
    }
  }
  return ""
}

function Get-HashKey([string]$Key) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $md5.ComputeHash($bytes)
  return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
}

function Apply-Dedupe([object]$Seconds, [string]$Key) {
  $secondsValue = 0
  if (-not [int]::TryParse([string]$Seconds, [ref]$secondsValue)) { return }
  if ($secondsValue -le 0) { return }

  $stateFile = Join-Path $StateDir ("{0}.last" -f (Get-HashKey $Key))
  $epoch = [datetime]"1970-01-01T00:00:00Z"
  $now = [int64](([datetime]::UtcNow - $epoch).TotalSeconds)
  $last = 0
  if (Test-Path -LiteralPath $stateFile) {
    [int64]::TryParse((Get-Content -LiteralPath $stateFile -Raw), [ref]$last) | Out-Null
  }
  if ($last -gt 0) {
    $age = $now - $last
    if ($age -ge 0 -and $age -lt $secondsValue) {
      $Script:Suppressed = $true
      $Script:SuppressionReason = "dedupe:{0}s" -f $age
      return
    }
  }
  Set-Content -LiteralPath $stateFile -Value ([string]$now) -NoNewline -Encoding ASCII
}

function Write-JsonLine([string]$Path, [object]$Entry) {
  $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
  $json = $Entry | ConvertTo-Json -Compress -Depth 8
  [System.IO.File]::AppendAllText($Path, $json + [Environment]::NewLine, $encoding)
}

function Invoke-WithStoreLock([scriptblock]$Action) {
  $lockKey = Get-HashKey $DataDir
  $mutex = [System.Threading.Mutex]::new($false, "Local\AISessionNotifier-$lockKey")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(3000)
    if ($acquired) { & $Action }
  } finally {
    if ($acquired) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
  }
}

function Write-SharedLedger {
  if (-not (Test-Enabled (Get-ConfigValue "ledger.enabled" $true))) { return }

  $max = [int](Get-ConfigValue "ledger.maxMessageChars" 260)
  if ($max -le 0) { $max = 260 }
  $savedLastMessage = ""
  if (Test-Enabled (Get-ConfigValue "ledger.includeMessageExcerpt" $false)) {
    $savedLastMessage = [string]$Script:LastMessage
  }
  if ($savedLastMessage.Length -gt $max) {
    $savedLastMessage = $savedLastMessage.Substring(0, [Math]::Max(0, $max - 3)) + "..."
  }

  $entry = [ordered]@{
    schemaVersion = 1
    timestamp = ([datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
    tool = "Kimi Code"
    event = $Script:EventName
    notificationType = $Script:NotificationType
    category = $Script:Category
    threadId = $Script:SessionId
    source = "kimi-code"
    cwd = $Script:Cwd
    targetUrl = $Script:TargetUrl
    title = $Script:Title
    message = $Script:Message
    lastAssistantMessage = $savedLastMessage
    suppressed = [bool]$Script:Suppressed
    suppressionReason = $Script:SuppressionReason
  }

  Invoke-WithStoreLock {
    Write-JsonLine $EventsFile $entry

    $registry = $null
    try {
      if (Test-Path -LiteralPath $SessionsFile) {
        $registry = Get-Content -LiteralPath $SessionsFile -Raw -Encoding UTF8 | ConvertFrom-Json
      }
    } catch {
      $registry = $null
    }
    if ($null -eq $registry) {
      $registry = [pscustomobject]@{
        version = 1
        updatedAt = ""
        sessions = [pscustomobject]@{}
      }
    }
    if ($null -eq $registry.sessions) {
      $registry | Add-Member -NotePropertyName sessions -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $identity = if ($Script:SessionId) { $Script:SessionId } else { $Script:Cwd }
    if (-not [string]::IsNullOrWhiteSpace($identity)) {
      $key = "kimi-code:$identity"
      $registry.sessions | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]$entry) -Force
      $registry.updatedAt = $entry.timestamp
      $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
      $tempFile = "$SessionsFile.tmp.$PID"
      [System.IO.File]::WriteAllText($tempFile, ($registry | ConvertTo-Json -Depth 10), $encoding)
      Move-Item -LiteralPath $tempFile -Destination $SessionsFile -Force
    }
  }
}

function Invoke-StorageCleanupIfDue {
  $marker = Join-Path $StateDir "cleanup.last"
  $now = [datetime]::UtcNow
  if (Test-Path -LiteralPath $marker) {
    try {
      if (($now - (Get-Item -LiteralPath $marker).LastWriteTimeUtc).TotalHours -lt 24) { return }
    } catch {}
  }

  $retentionDays = [int](Get-ConfigValue "ledger.retentionDays" 30)
  if ($retentionDays -lt 0) { $retentionDays = 30 }
  $maxBytes = [int64](Get-ConfigValue "ledger.maxBytes" 5242880)
  $cutoff = $now.AddDays(-$retentionDays)

  Invoke-WithStoreLock {
    if (Test-Path -LiteralPath $EventsFile) {
      $kept = New-Object System.Collections.Generic.List[string]
      foreach ($line in [System.IO.File]::ReadLines($EventsFile)) {
        try {
          $event = $line | ConvertFrom-Json
          $timestamp = [datetime]::Parse([string]$event.timestamp).ToUniversalTime()
          if ($timestamp -ge $cutoff) { $kept.Add($line) }
        } catch {}
      }
      if ($maxBytes -gt 0) {
        $bounded = New-Object System.Collections.Generic.List[string]
        $bytes = [int64]0
        for ($index = $kept.Count - 1; $index -ge 0; $index--) {
          $size = [System.Text.Encoding]::UTF8.GetByteCount($kept[$index] + [Environment]::NewLine)
          if ($bounded.Count -gt 0 -and ($bytes + $size) -gt $maxBytes) { break }
          $bounded.Insert(0, $kept[$index])
          $bytes += $size
        }
        $kept = $bounded
      }
      $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
      $content = if ($kept.Count) { ($kept -join [Environment]::NewLine) + [Environment]::NewLine } else { "" }
      [System.IO.File]::WriteAllText($EventsFile, $content, $encoding)
    }

    if (Test-Path -LiteralPath $SessionsFile) {
      try {
        $registry = Get-Content -LiteralPath $SessionsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in @($registry.sessions.PSObject.Properties)) {
          $timestamp = [datetime]::Parse([string]$property.Value.timestamp).ToUniversalTime()
          if ($timestamp -lt $cutoff) { $registry.sessions.PSObject.Properties.Remove($property.Name) }
        }
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText($SessionsFile, ($registry | ConvertTo-Json -Depth 10), $encoding)
      } catch {}
    }
  }
  Set-Content -LiteralPath $marker -Value ([string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -NoNewline -Encoding ASCII
}

function Ensure-NativeMethods {
  try {
    [AISessionNotifier.NativeMethods] | Out-Null
    return
  } catch {}

  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace AISessionNotifier {
  public static class NativeMethods {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  }
}
"@
}

function Focus-VSCodeWindowByPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  Ensure-NativeMethods

  $workspaceName = Split-Path -Path $Path -Leaf
  $parentPath = Split-Path -Path $Path -Parent
  $parentName = if ($parentPath) { Split-Path -Path $parentPath -Leaf } else { "" }
  $tokens = @($Path, $workspaceName, $parentName) | Where-Object { $_ -and $_.Length -gt 1 } | Select-Object -Unique
  $processNames = @("Code", "Code - Insiders", "VSCodium")

  foreach ($name in $processNames) {
    foreach ($process in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
      if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
      $title = [string]$process.MainWindowTitle
      if ([string]::IsNullOrWhiteSpace($title)) { continue }
      foreach ($token in $tokens) {
        if ($title.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
          [AISessionNotifier.NativeMethods]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
          [AISessionNotifier.NativeMethods]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
          return $true
        }
      }
    }
  }

  return $false
}

function Focus-KimiWindowByPath([string]$Path) {
  Ensure-NativeMethods

  $tokens = @()
  if (-not [string]::IsNullOrWhiteSpace($Path)) {
    $workspaceName = Split-Path -Path $Path -Leaf
    $parentPath = Split-Path -Path $Path -Parent
    $parentName = if ($parentPath) { Split-Path -Path $parentPath -Leaf } else { "" }
    $tokens = @($Path, $workspaceName, $parentName) |
      Where-Object { $_ -and $_.Length -gt 1 } |
      Select-Object -Unique
  }

  $processNames = @(
    "Code", "Code - Insiders", "Cursor", "WindowsTerminal", "wezterm-gui",
    "Alacritty", "Warp", "pwsh", "powershell", "cmd"
  )
  $fallback = $null

  foreach ($name in $processNames) {
    foreach ($process in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
      if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
      if ($null -eq $fallback) { $fallback = $process }
      $title = [string]$process.MainWindowTitle
      if ([string]::IsNullOrWhiteSpace($title)) { continue }
      foreach ($token in $tokens) {
        if ($title.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
          [AISessionNotifier.NativeMethods]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
          [AISessionNotifier.NativeMethods]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
          return $true
        }
      }
    }
  }

  if ($null -ne $fallback) {
    [AISessionNotifier.NativeMethods]::ShowWindow($fallback.MainWindowHandle, 9) | Out-Null
    [AISessionNotifier.NativeMethods]::SetForegroundWindow($fallback.MainWindowHandle) | Out-Null
    return $true
  }
  return $false
}

function Open-VSCodeWorkspace([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $commands = @("code.cmd", "code-insiders.cmd", "codium.cmd", "code", "code-insiders", "codium")
  foreach ($command in $commands) {
    $found = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $found) {
      Start-Process -FilePath $found.Source -ArgumentList @("-r", $Path) | Out-Null
      return $true
    }
  }
  return $false
}

function Test-IsVSCodeTarget([string]$Bundle, [string]$Url) {
  if ($Bundle -eq "com.microsoft.VSCode") { return $true }
  if ($Url -match "^vscode:") { return $true }
  return $false
}

function Open-Target([string]$Url, [string]$Bundle, [string]$Path, [string]$OpenWorkspace, [string]$FocusWindow) {
  if ($Bundle -eq "kimi-code") {
    Focus-KimiWindowByPath $Path | Out-Null
    return
  }

  $isVSCode = Test-IsVSCodeTarget $Bundle $Url
  $shouldFocus = (Test-Enabled $FocusWindow)
  $shouldOpenWorkspace = (Test-Enabled $OpenWorkspace)

  if ($isVSCode -and $shouldFocus) {
    Focus-VSCodeWindowByPath $Path | Out-Null
    Start-Sleep -Milliseconds 120
  }

  if ($isVSCode -and $shouldOpenWorkspace) {
    Open-VSCodeWorkspace $Path | Out-Null
    Start-Sleep -Milliseconds 350
  }

  if (-not [string]::IsNullOrWhiteSpace($Url)) {
    Start-Process $Url | Out-Null
  }

  if ($isVSCode -and $shouldFocus) {
    Start-Sleep -Milliseconds 350
    Focus-VSCodeWindowByPath $Path | Out-Null
  }
}

function Show-NotifierDialog(
  [string]$Title,
  [string]$Message,
  [string]$Url,
  [string]$Path,
  [int]$TimeoutSeconds,
  [string]$IconPath,
  [bool]$CanOpen,
  [string]$OpenButtonLabel,
  [string]$OkButtonLabel,
  [string]$DismissButtonLabel
) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = $Title
  $form.StartPosition = "CenterScreen"
  $form.TopMost = $true
  $form.Width = 460
  $form.Height = 190
  $form.FormBorderStyle = "FixedDialog"
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Message
  $label.Left = 18
  $label.Top = 18
  $label.Width = 410
  $label.Height = 78

  $picture = $null
  if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
    try {
      $picture = New-Object System.Windows.Forms.PictureBox
      $picture.Left = 18
      $picture.Top = 18
      $picture.Width = 64
      $picture.Height = 64
      $picture.SizeMode = "Zoom"
      $picture.Image = [System.Drawing.Image]::FromFile($IconPath)
      $form.Controls.Add($picture)
      $label.Left = 100
      $label.Width = 328
    } catch {
      $picture = $null
    }
  }
  $form.Controls.Add($label)

  $openButton = New-Object System.Windows.Forms.Button
  $openButton.Text = if ($CanOpen) { $OpenButtonLabel } else { $OkButtonLabel }
  $openButton.Width = 125
  $openButton.Height = 30
  $openButton.Left = 178
  $openButton.Top = 112
  $form.Controls.Add($openButton)

  $dismissButton = New-Object System.Windows.Forms.Button
  $dismissButton.Text = $DismissButtonLabel
  $dismissButton.Width = 92
  $dismissButton.Height = 30
  $dismissButton.Left = 316
  $dismissButton.Top = 112
  $form.Controls.Add($dismissButton)

  $Script:DialogAction = "dismiss"
  $openButton.Add_Click({
    $Script:DialogAction = "open"
    $form.Close()
  })
  $dismissButton.Add_Click({
    $Script:DialogAction = "dismiss"
    $form.Close()
  })

  if ($TimeoutSeconds -gt 0) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1, $TimeoutSeconds) * 1000
    $timer.Add_Tick({
      $Script:DialogAction = "timeout"
      $timer.Stop()
      $form.Close()
    })
    $timer.Start()
  }

  [void]$form.ShowDialog()
  if ($null -ne $picture -and $null -ne $picture.Image) { $picture.Image.Dispose() }
  return $Script:DialogAction
}

Ensure-AppState

if ($OpenTarget) {
  Open-Target $TargetUrl $BundleId $CwdPath $OpenWorkspaceFirst $FocusVSCodeWindow
  exit 0
}

$raw = [Console]::In.ReadToEnd()
$payload = $null
try {
  if ($raw.Trim().Length -gt 0) { $payload = $raw | ConvertFrom-Json }
} catch {
  $payload = $null
}

$Script:EventName = Get-JsonValue $payload @("hook_event_name", "event_name", "eventName")
$Script:NotificationType = Get-JsonValue $payload @("notification_type", "type")
$Script:SessionId = Get-JsonValue $payload @("session_id", "sessionId", "conversation_id", "conversationId", "thread_id", "threadId")
$Script:Cwd = Get-JsonValue $payload @("cwd", "workspace_dir", "project_dir")
if ([string]::IsNullOrWhiteSpace($Script:Cwd)) { $Script:Cwd = (Get-Location).Path }
$Script:LastMessage = Get-JsonValue $payload @("last_assistant_message", "lastAssistantMessage", "message")
$Script:NotificationLocale = Resolve-NotificationLocale

$Script:Category = "attention"
switch ($Script:EventName) {
  "PermissionRequest" {
    $Script:Category = "permission"
    $soundKind = "Exclamation"
  }
  "Stop" {
    $Script:Category = "stop"
    $soundKind = "Asterisk"
  }
  "StopFailure" {
    $Script:Category = "error"
    $soundKind = "Exclamation"
  }
  "Notification" {
    if ($Script:NotificationType -eq "task.completed") {
      $Script:Category = "completion"
    }
    $soundKind = "Asterisk"
  }
  default {
    $soundKind = "Asterisk"
  }
}

if ($Script:NotificationLocale -eq "zh-CN") {
  $openButtonLabel = "打开会话"
  $okButtonLabel = "知道了"
  $dismissButtonLabel = "关闭"
  switch ($Script:EventName) {
    "PermissionRequest" {
      $Script:Title = "Kimi Code 正在等待权限确认"
      $Script:Message = "请批准或拒绝权限请求以继续。"
    }
    "Stop" {
      $Script:Title = "Kimi Code 本轮已停下"
      $Script:Message = "本轮回复已经停止，可以回来查看了。"
    }
    "StopFailure" {
      $Script:Title = "Kimi Code 本轮执行失败"
      $Script:Message = "本轮因错误停止，需要回来检查。"
    }
    "Notification" {
      if ($Script:NotificationType -eq "task.completed") {
        $Script:Title = "Kimi Code 后台任务已完成"
        $Script:Message = "后台任务已经完成，可以回来查看了。"
      } else {
        $Script:Title = "Kimi Code 有一条新提醒"
        $Script:Message = "Kimi Code 需要你查看。"
      }
    }
    default {
      $Script:Title = "Kimi Code 有一条新提醒"
      $Script:Message = "Kimi Code 需要你查看。"
    }
  }
} else {
  $openButtonLabel = "Open session"
  $okButtonLabel = "OK"
  $dismissButtonLabel = "Dismiss"
  switch ($Script:EventName) {
    "PermissionRequest" {
      $Script:Title = "Kimi Code needs permission"
      $Script:Message = "Approve or reject the permission request to continue."
    }
    "Stop" {
      $Script:Title = "Kimi Code turn stopped"
      $Script:Message = "The current turn stopped and is ready for review."
    }
    "StopFailure" {
      $Script:Title = "Kimi Code turn failed"
      $Script:Message = "The current turn stopped because of an error and needs review."
    }
    "Notification" {
      if ($Script:NotificationType -eq "task.completed") {
        $Script:Title = "Kimi Code background task finished"
        $Script:Message = "A background task finished and is ready for review."
      } else {
        $Script:Title = "Kimi Code notification"
        $Script:Message = "Kimi Code needs your attention."
      }
    }
    default {
      $Script:Title = "Kimi Code notification"
      $Script:Message = "Kimi Code needs your attention."
    }
  }
}

$Script:TargetUrl = ""
$Script:IconPath = Resolve-KimiIconPath

$Script:Suppressed = $false
$Script:SuppressionReason = ""
if (-not (Test-Enabled (Get-ConfigValue "notifications.enabled" $true))) {
  $Script:Suppressed = $true
  $Script:SuppressionReason = "notifications_disabled"
}

if (-not $Script:Suppressed) {
  Apply-Dedupe (Get-ConfigValue "noise.dedupeSeconds" 20) ("kimi-code|{0}|{1}|{2}|{3}" -f $Script:EventName, $Script:NotificationType, $Script:SessionId, $Script:Cwd)
}

Write-SharedLedger
Invoke-StorageCleanupIfDue

if ($Script:Suppressed) { exit 0 }

if (Test-Enabled $env:AI_SESSION_NOTIFIER_DRY_RUN) { exit 0 }

if (Test-Enabled (Get-ConfigValue "notifications.sound" $true)) {
  if ($soundKind -eq "Exclamation") {
    [System.Media.SystemSounds]::Exclamation.Play()
  } else {
    [System.Media.SystemSounds]::Asterisk.Play()
  }
}

if (Test-Enabled (Get-ConfigValue "notifications.dialogs" $true)) {
  $timeout = if ($Script:EventName -eq "PermissionRequest") { 30 } elseif ($Script:EventName -eq "StopFailure") { 12 } else { 8 }
  $action = Show-NotifierDialog $Script:Title $Script:Message $Script:TargetUrl $Script:Cwd $timeout $Script:IconPath $true $openButtonLabel $okButtonLabel $dismissButtonLabel
  if ($action -eq "open") {
    Open-Target $Script:TargetUrl "kimi-code" $Script:Cwd (Get-ConfigValue "routing.openWorkspaceFirst" $true) (Get-ConfigValue "routing.focusVSCodeWindow" $true)
  }
} else {
  Write-Host ("{0}: {1}" -f $Script:Title, $Script:Message)
}
