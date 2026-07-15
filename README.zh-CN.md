# dylon-tiny-kits

Dylon Cai 制作的一组小而实用的工具与可复用 Agent Skills。

[English](README.md)

每个项目都力求能够被独立理解、安装和卸载，并清楚说明兼容范围，采用重视隐私的默认配置。

## 工具

| 项目 | 用途 | 支持范围 |
| --- | --- | --- |
| [AI Session Notifier](tools/ai-session-notifier/README.zh-CN.md) | 为 AI 编码会话提供隐私优先的桌面提醒、有限容量的本地记录和尽力返回原会话。 | macOS 上的 Codex；macOS、Linux、Windows 上的 Claude Code |

## Skills

能够脱离某个具体工具、被多个工作流复用的 Agent Skill 放在
[`skills/`](skills/)；只服务于单个工具的 Skill 则与工具放在一起。

## 仓库结构

```text
tools/       可独立使用的工具及其智能体适配器
skills/      可复用的 Agent 工作流
templates/   面向人或智能体的项目模板
docs/        仓库级规范
```

## 项目原则

每个项目保持自包含：工具专用的文档、测试、适配器和更新记录与工具放在一起；能够跨项目独立复用的工作流放在 `skills/` 下。

## 许可证

除非子项目另有说明，本仓库代码采用 [MIT License](LICENSE)。
