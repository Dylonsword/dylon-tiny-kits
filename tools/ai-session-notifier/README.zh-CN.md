# AI Session Notifier

**AI Session Notifier** 会在 Codex、Claude Code 或 Kimi Code 停下、空闲、失败或等待权限时显示桌面提醒，并尽力返回原来的应用、工作区和会话；其 Codex 适配器以 `codex-notify-hooks` 插件形式提供。

[English](README.md)

## 功能概览

| 功能 | 行为 |
| --- | --- |
| Codex 提醒 | 监听 `Stop` 和 `PermissionRequest`。 |
| Claude Code 提醒 | 监听权限请求和空闲事件。 |
| Kimi Code 提醒 | 监听本轮停止、权限请求、执行失败和后台任务完成事件。 |
| 通知语言 | 三套适配器统一跟随系统语言，也可以固定为简体中文或英文。 |
| 返回会话 | 根据 hook 元数据自动选择 Codex 桌面端、VS Code、Claude Code 或启动 Kimi 的终端宿主。 |
| 多窗口定位 | 打开会话链接前，先尽力抬起匹配的 VS Code 工作区窗口。 |
| 降噪 | 合并短时间重复提醒，并识别可能仍在观察/等待的任务。 |
| 本地记录 | 保存有容量和保留期上限的事件，只保留每个会话最新路由。 |
| 管理能力 | 提供状态、诊断、清理、无 UI 测试和报告命令。 |

需要特别说明：Codex 和 Kimi Code 的 `Stop` 只表示**当前这一轮停下**，不等于整个任务或目标已完成；Claude Code 的 `idle_prompt` 也只表示当前会话正在等待。

## 安装

clone 仓库并进入仓库根目录，然后按本机需要选择适配器。

### macOS：准备全部适配器

```zsh
tools/ai-session-notifier/scripts/install.sh --all
```

只安装某一个适配器：

```zsh
tools/ai-session-notifier/scripts/install.sh --codex
tools/ai-session-notifier/scripts/install.sh --claude
tools/ai-session-notifier/scripts/install.sh --kimi
```

安装后先进行无弹窗验收：

```zsh
"$HOME/.local/bin/ai-session-notifier" doctor
"$HOME/.local/bin/ai-session-notifier" test --tool all --dry-run
```

`terminal-notifier` 只是可选依赖。安装器默认不会改动 Homebrew；希望通知中心横幅本身也可点击时，再显式运行：

```zsh
tools/ai-session-notifier/scripts/install.sh --all --install-deps
```

Claude CLI 会先从当前 `PATH` 查找，也兼容常见的 nvm 安装目录。

### 安装 Kimi Code 原生插件

Kimi Code 插件 hooks 要求 CLI `0.20.1` 或更新版本。先运行
`kimi --version`，然后进入 Kimi Code 执行：

```text
/plugins install /你的绝对路径/dylon-tiny-kits/tools/ai-session-notifier/kimi-code-plugin
/plugins enable ai-session-notifier
/reload
```

Kimi 会要求用户确认是否信任本地第三方插件。统一安装器只会打印上述命令，不会绕过这一步交互审查。事件和跳转细节见 [Kimi 适配器文档](kimi-code-plugin/README.md)。
Kimi Code for VS Code `0.6.0` 及以上版本使用内置 CLI 引擎并共享同一个 `KIMI_CODE_HOME`；请先通过新版 CLI 安装插件，再重新加载 VS Code 窗口，让扩展端一并载入。

### Linux / Windows：安装 Claude Code 插件

Codex 适配器目前只支持 macOS。仓库根目录本身就是 Claude Code marketplace：

```text
claude plugin marketplace add /你的绝对路径/dylon-tiny-kits
claude plugin install ai-session-notifier@dylon-tiny-kits --scope user
```

更新已有安装：

```text
claude plugin update ai-session-notifier@dylon-tiny-kits --scope user
```

Windows 直接在 PowerShell 或命令提示符中执行，Claude Code 会自动选择 `bin/ai-session-notify.cmd`。

## 给 Codex / Claude Code / Kimi Code 等 Agent 的安装区

> 本节是给用户委托的编码 Agent 读取和执行的安装约定。所有操作都应限制在用户 clone 的 `dylon-tiny-kits` 仓库和下文列出的用户级目录中；不要假定维护者机器上的绝对路径。

1. 从当前 clone 解析仓库根目录，确认存在 `tools/ai-session-notifier/tool.json`，不要硬编码 `/Users/...`。
2. 检测操作系统和用户要求的适配端。Codex 仅支持 macOS；Claude Code 和 Kimi Code 支持 macOS、Linux、Windows。不要声称已经在 Linux/Windows 安装 Codex 适配器。
3. macOS 安装前先预览：

   ```zsh
   tools/ai-session-notifier/scripts/install.sh --all --dry-run
   ```

4. 根据用户要求运行 `--all`、`--codex`、`--claude` 或 `--kimi`。只有用户明确同意修改包管理器时，才可添加 `--install-deps`。
5. Linux/Windows 使用上面的 Claude CLI 命令安装或更新 `ai-session-notifier@dylon-tiny-kits`，不要手工修改 Claude 插件缓存。
6. Kimi Code 必须是 `0.20.1` 或更新版本；使用 `/plugins install` 安装本地 `kimi-code-plugin`，由用户确认第三方信任，再运行 `/plugins enable ai-session-notifier` 和 `/reload`。不要手工修改 Kimi 的托管插件注册表。
7. 不要直接覆盖 `~/.codex/hooks.json`。必须使用安装器，让它备份并合并本工具自己的 hook；不要使用 `sudo`。
8. 安装后默认执行无 UI 验收：

   ```sh
   "$HOME/.local/bin/ai-session-notifier" doctor
   "$HOME/.local/bin/ai-session-notifier" test --tool all --dry-run
   ```

   如果系统没有安装管理命令，则从源码使用 Python 3.9 及以上版本运行：

   ```sh
   python3 tools/ai-session-notifier/scripts/ai-session-notifier doctor
   python3 tools/ai-session-notifier/scripts/ai-session-notifier test --tool all --dry-run
   ```

9. 除非用户明确接受隐私取舍，否则不要开启消息摘要、原始 payload 或调试日志。安装和排障过程中绝不能运行卸载命令的 `--purge`。
10. 完成后向用户报告：安装了哪些适配器、版本、修改路径、`doctor` 结果和剩余警告。提醒用户 Claude Code 更新后需要重启，Kimi Code 需要 `/reload` 或新会话；Codex hook 变化后可能需要在新任务中审查并信任 hook。

用户明确希望看真实弹窗时，可以运行 `ai-session-notifier test --tool <tool>`；Agent 默认验收必须使用 `--dry-run`，避免突然打断桌面工作。

## 默认隐私策略

通知器本身不调用网络服务，所有记录只保存在本机。

| 项目 | 默认值 |
| --- | --- |
| 保存助手消息摘要 | 关闭 |
| 保存原始 hook payload | 关闭 |
| 调试日志 | 关闭 |
| 事件保留期 | 30 天 |
| 事件文件容量上限 | 5 MiB |
| Unix 配置/数据权限 | 目录 `0700`，文件 `0600` |

事件记录仍会包含工具名、事件类型、工作区路径、会话 ID、目标链接和通知标题等路由信息。如果这些信息也属于敏感数据，可以关闭 `ledger.enabled`，或者在卸载时使用 `--purge`。

从旧版本升级到 schema 2 时，只要用户没有显式开启 `ledger.includeMessageExcerpt`，历史助手消息摘要也会被自动清空。

## 管理命令

macOS 安装器会把下列命令放到 `~/.local/bin`：

```sh
ai-session-notifier status
ai-session-notifier doctor
ai-session-notifier cleanup --dry-run
ai-session-notifier cleanup
ai-session-notifier test --tool all
ai-session-report --hours 24
```

也可以直接从 clone 下来的仓库运行，要求 Python 3.9 及以上：

```sh
python3 tools/ai-session-notifier/scripts/ai-session-notifier doctor
python3 tools/ai-session-notifier/scripts/ai-session-report --hours 24
```

`init`、`status`、`doctor`、`cleanup` 和报告命令都支持 `--json`，方便后续被其他脚本或智能体调用。

## 跳转原理与限制

`sessions.json` 只保存每个会话最新的一条路由。通知触发时，适配器根据来源自动选择 Codex 桌面端、VS Code、Claude Code 或启动 Kimi 的终端宿主，不再让用户手动判断“这个任务当时在哪个 App”。

macOS 上的 VS Code Codex 会话会依次尝试：

1. 根据工作区路径或目录名抬起匹配的 VS Code 窗口；
2. 让 VS Code 打开对应工作区；
3. 打开 `vscode://openai.chatgpt/local/<thread_id>`；
4. 再次抬起匹配窗口。

Codex 桌面端使用 `codex://threads/<thread_id>`；Claude Code 使用 `claude-cli://open` 目录链接。Kimi Code 目前没有公开的会话 deep link，因此只能激活原终端或 VS Code，并按工作区标题尽力抬起匹配窗口。Windows 也包含对应的标题匹配逻辑。

这里必须诚实地说是“尽力跳回”：VS Code 和宿主应用并没有在所有配置中提供一个稳定的公开参数，用来精确指定某个已存在的窗口。macOS 的窗口抬起还需要给 System Events 辅助功能权限。匹配失败时，工具仍会退回到正常打开工作区和会话链接。

## 平台支持

| 平台 | Codex | Claude Code | Kimi Code CLI |
| --- | --- | --- | --- |
| macOS | 已实测。支持 `terminal-notifier`/AppleScript、Codex App 与 VS Code 路由、多窗口尽力定位。 | 已实测。支持 `terminal-notifier`/AppleScript 和 `claude-cli://`。 | 已使用 Kimi Code CLI `0.26.0` 完成原生插件实测；要求 CLI `0.20.1` 或更新版本。支持 `terminal-notifier`/AppleScript 和终端/VS Code 窗口尽力定位。 |
| Linux | 暂未封装。 | 已包含 `notify-send` 适配器并通过自动测试，仍需要更多桌面环境实测。 | 已包含原生插件 shell/`notify-send` 适配器，仍需要桌面实测。 |
| Windows | 暂未封装。 | 已包含 PowerShell 对话框、加锁事件记录、自动清理和 VS Code 尽力聚焦；有自动检查，仍需要真机体验验证。 | 通过 Kimi 所需的 Git Bash 启动 PowerShell 对话框，支持加锁记录和终端/VS Code 尽力聚焦，仍需要真机体验验证。 |

macOS 会优先读取本机 ChatGPT/Claude 应用或 OpenAI、Anthropic、Moonshot AI 官方 VS Code 扩展中的图标。也可以为三个工具分别指定本地图标；仓库本身不分发厂商 Logo 文件。

## 配置与数据

| 数据 | macOS/Linux | Windows |
| --- | --- | --- |
| 配置 | `~/.config/ai-session-notifier/config.json` | `%APPDATA%\ai-session-notifier\config.json` |
| 事件 | `~/.local/share/ai-session-notifier/events.jsonl` | `%LOCALAPPDATA%\ai-session-notifier\events.jsonl` |
| 会话路由 | `~/.local/share/ai-session-notifier/sessions.json` | `%LOCALAPPDATA%\ai-session-notifier\sessions.json` |

支持 `XDG_CONFIG_HOME`、`XDG_DATA_HOME` 和 `AI_SESSION_NOTIFIER_*` 环境变量。完整配置见 [config.example.json](config.example.json)。

常用字段：

- `notifications.enabled`：总通知开关。
- `notifications.dialogs`：显示醒目的 macOS/Windows 对话框。
- `notifications.sound`：声音开关。
- `notifications.locale`：可设为 `auto`（默认）、`zh-CN` 或 `en`。自动模式会为 `zh`、`zh-CN`、`zh-Hans`、`zh-SG` 系统区域显示简体中文，其他区域显示英文。
- `notifications.codexIconPath`、`notifications.claudeIconPath`、`notifications.kimiIconPath`：分别覆盖三个工具的本地图标。
- `notifications.iconPath`：所有工具共用的兜底图标。
- `noise.dedupeSeconds`：重复事件静默时间。
- `noise.observationMode`：可能处于观察窗口时使用 `notify` 或 `quiet`。
- `ledger.includeMessageExcerpt`：显式选择保存短消息摘要。
- `ledger.retentionDays`、`ledger.maxBytes`：本地存储上限。
- `debug.saveRawPayload`：显式选择保存最近一次原始 payload。
- `routing.openWorkspaceFirst`、`routing.focusVSCodeWindow`：控制 VS Code 尽力定位。

环境变量 `AI_SESSION_NOTIFIER_LOCALE` 的优先级高于配置文件，可在单个进程或 shell 环境中临时指定 `zh-CN` 或 `en`。

适配器每天最多自动清理一次；也可以用管理命令随时清理。旧的追加式 `session-registry.jsonl` 会自动迁移为紧凑路由表。

## 卸载

只删除适配器，保留管理命令和本地记录：

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all
```

先预览完整清除：

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all --purge --dry-run
```

确认后清除适配器、配置、记录、路由表和已安装命令：

```zsh
tools/ai-session-notifier/scripts/uninstall.sh --all --purge
```

Codex 卸载器只移除本工具写入的 `Stop`、`PermissionRequest` 项，不会删除其他 hooks；安装器修改共享配置前会先备份。Kimi 插件需通过 `/plugins remove ai-session-notifier` 交互移除，以保持其注册表一致。

## 开发验证

```sh
tools/ai-session-notifier/tests/run-tests.sh
```

测试覆盖默认脱敏、私有权限、保留期、旧数据迁移、Kimi 事件语义、并发写入、安装后命令查找，以及安装/卸载时保留无关 Codex hooks。GitHub Actions 会在 macOS、Linux、Windows 上运行相应检查。

Codex、Claude、Kimi 等名称与商标归各自权利人所有。本工具是社区项目，与 OpenAI、Anthropic、Moonshot AI 无隶属或背书关系。
