<div align="center">

# dylon-tiny-kits

### 自己先用起来，再把真正省事的小工具开源出来

[![CI](https://github.com/Dylonsword/dylon-tiny-kits/actions/workflows/ci.yml/badge.svg)](https://github.com/Dylonsword/dylon-tiny-kits/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-2f855a.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-3b4252.svg)](#平台支持)

**简体中文** · [English](README.en.md) · [GitHub](https://github.com/Dylonsword/dylon-tiny-kits) · [Gitee](https://gitee.com/dylontfif/dylon-tiny-kits)

</div>

这里收录的是我在 AI 辅助开发中实际使用、持续打磨的小工具与 Agent Skills。它不追求大而全：每个项目都应该能独立理解、独立安装、独立卸载，并诚实说明平台支持、隐私边界和仍然存在的限制。

## 现在有什么

| 项目 | 一句话说明 | 适用范围 | 状态 |
| --- | --- | --- | --- |
| [AI Session Notifier](tools/ai-session-notifier/README.zh-CN.md) | Codex、Claude Code 或 Kimi Code 需要你查看时显示桌面提醒，并尽力一键返回原会话。 | macOS / Linux / Windows，具体适配范围见下文 | Beta，日常使用中 |

独立通用的 Agent Skills 会放在 [`skills/`](skills/)；只服务于某个工具的 Skill 会跟随工具一起维护。尚未达到可独立发布标准的内容不会提前放进目录占位。

## 最快安装

### 交给 Agent

在 Codex、Claude Code、Kimi Code 或其他编码 Agent 中直接发送：

```text
请帮我安装 dylon-tiny-kits 里的 AI Session Notifier：
https://github.com/Dylonsword/dylon-tiny-kits/tree/main/tools/ai-session-notifier

先阅读 README 中“给 Codex / Claude Code / Kimi Code 等 Agent 的安装区”，
只安装当前系统支持的适配器；不要未经确认修改包管理器。
安装后运行 doctor 和 --dry-run 测试，并向我报告结果。
```

工具文档中专门保留了面向 Agent 的安装约定，因此不需要用户记住 hook、插件缓存或配置文件的具体路径。

### macOS 手动安装

```zsh
git clone https://github.com/Dylonsword/dylon-tiny-kits.git
cd dylon-tiny-kits
tools/ai-session-notifier/scripts/install.sh --all --dry-run
tools/ai-session-notifier/scripts/install.sh --all
```

安装器会提示仍需用户确认的 Kimi Code 插件信任步骤。Linux、Windows、单独安装某个适配器以及卸载方式，请看 [AI Session Notifier 完整文档](tools/ai-session-notifier/README.zh-CN.md)。

## AI Session Notifier

> 同时开着几个 VS Code 窗口、一个 Codex 桌面任务，再加上 Claude Code 或 Kimi Code 时，不应该靠反复切窗口确认谁已经做完、谁还在等权限。

AI Session Notifier 把各个编码 Agent 的生命周期 hook 接到统一的本地提醒、会话路由和有限容量事件记录上。

### 它能做什么

| 能力 | 行为 |
| --- | --- |
| 明显提醒 | 识别本轮停止、权限请求、空闲、失败和后台任务完成等受支持事件。 |
| 一键返回 | 自动判断事件来自 Codex App、VS Code、Claude Code 或 Kimi Code 的终端宿主。 |
| 多窗口定位 | 根据工作区和会话信息尽力抬起对应窗口，再打开会话链接。 |
| 智能降噪 | 合并重复事件；Codex 开启“替我审批”时，不再为自动处理的权限请求反复弹窗。 |
| 中英双语 | 默认跟随系统语言，也可以固定为简体中文或英文。 |
| 本地记录 | 保存有保留期和容量上限的事件账本，只保留每个会话的最新路由。 |
| 可诊断、可卸载 | 提供 `status`、`doctor`、清理、无 UI 测试和完整卸载命令。 |

### 默认隐私边界

- 通知器本身不调用网络服务，状态保存在本机。
- 默认不保存助手消息摘要、原始 hook payload 或调试日志。
- Unix 配置目录使用 `0700`，配置和事件文件使用 `0600`。
- 仓库不重新分发 Codex、Claude 或 Kimi 的 Logo，只读取本机已安装应用或官方扩展中的图标。

### 需要知道的限制

- `Stop` 只表示当前这一轮停下，不代表整个长期任务已经最终完成。
- VS Code 和宿主应用没有在所有环境中提供稳定的精确窗口接口，因此跳转是尽力而为。
- Kimi Code 暂无公开会话 deep link，目前只能按终端宿主和工作区尽力返回。
- Linux 和 Windows 已有自动测试覆盖，但部分桌面行为仍欢迎真机反馈。

[完整功能与安装说明](tools/ai-session-notifier/README.zh-CN.md) · [更新记录](tools/ai-session-notifier/CHANGELOG.md) · [配置示例](tools/ai-session-notifier/config.example.json)

## 平台支持

| 平台 | Codex | Claude Code | Kimi Code |
| --- | --- | --- | --- |
| macOS | 已实测；支持 Codex App、VS Code、通知图标与多窗口尽力定位 | 已实测 | 原生插件已实测 |
| Linux | 暂未封装 | 已包含适配器和自动测试，仍需更多桌面实测 | 已包含适配器和自动测试，仍需桌面实测 |
| Windows | 暂未封装 | 已包含 PowerShell 对话框和窗口定位，仍需真机体验验证 | 已包含 PowerShell 对话框和窗口定位，仍需真机体验验证 |

## 仓库结构

```text
tools/       可独立安装的小工具及其 Agent 适配器
skills/      可脱离单个工具复用的 Agent Skills
templates/   面向人或 Agent 的项目模板
docs/        仓库级发布与维护规范
```

每个工具的实现、适配器、测试、文档和更新记录放在同一个子目录中。这样 clone 整个仓库很方便，只取其中一个工具也不会牵出一串隐含依赖。

## 发布原则

- **先解决真实问题**：自己实际使用和验证过，再整理成对外工具。
- **默认尊重隐私**：只收集实现功能所需的最少本地信息，高敏感记录必须显式开启。
- **安装与卸载对称**：写清修改了什么，也提供可预览、可恢复的卸载路径。
- **不隐藏边界**：自动测试不等于真机实测，尽力跳转不写成精确跳转。
- **对 Agent 友好**：除了给人看的步骤，也写明 Agent 应如何安全地完成安装和验收。

## 反馈

仓库由 [Dylon Cai](https://github.com/Dylonsword) 维护。遇到问题或有适配建议，可以在 GitHub Issues 中留下复现环境和日志中的脱敏信息。这个仓库里的工具对你有帮助，欢迎点一个 Star，让我知道哪些方向值得继续打磨。

## 许可证

除非子项目另有说明，本仓库代码采用 [MIT License](LICENSE)。Codex、Claude、Kimi 等名称与商标归各自权利人所有，本项目与 OpenAI、Anthropic、Moonshot AI 无隶属或背书关系。
