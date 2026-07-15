from __future__ import annotations

import json
import unittest
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_ROOT.parents[1]


class MetadataTests(unittest.TestCase):
    def test_versions_and_identity_are_consistent(self) -> None:
        tool = json.loads((TOOL_ROOT / "tool.json").read_text(encoding="utf-8"))
        codex = json.loads((TOOL_ROOT / "codex-plugin" / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
        claude = json.loads((TOOL_ROOT / "claude-code-plugin" / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))

        self.assertEqual(tool["version"], "0.4.1")
        self.assertEqual(codex["version"].split("+")[0], "0.4.1")
        self.assertEqual(claude["version"], "0.4.1")
        self.assertEqual(tool["author"]["name"], "Dylon Cai")

    def test_codex_plugin_contains_current_management_commands(self) -> None:
        for name in ("ai-session-notifier", "ai-session-report"):
            shared = TOOL_ROOT / "scripts" / name
            packaged = TOOL_ROOT / "codex-plugin" / "scripts" / name
            self.assertEqual(packaged.read_bytes(), shared.read_bytes(), f"stale packaged {name}")

    def test_repository_does_not_redistribute_provider_logos(self) -> None:
        forbidden = [
            TOOL_ROOT / "codex-plugin" / "assets" / "codex-logo.png",
            TOOL_ROOT / "claude-code-plugin" / "assets" / "claude-code-logo.png",
        ]
        self.assertFalse(any(path.exists() for path in forbidden))

    def test_adapters_resolve_icons_from_local_official_installs(self) -> None:
        codex_script = (TOOL_ROOT / "codex-plugin" / "scripts" / "codex-notify.sh").read_text(
            encoding="utf-8"
        )
        claude_script = (TOOL_ROOT / "claude-code-plugin" / "bin" / "ai-session-notify").read_text(
            encoding="utf-8"
        )
        self.assertIn("ChatGPT.app/Contents/Resources/icon-codex-dark-color.png", codex_script)
        self.assertIn("openai.chatgpt-*/webview/assets/codex-app-ga-logo", codex_script)
        self.assertIn("anthropic.claude-code-*/resources/claude-logo.png", claude_script)

    def test_json_metadata_is_valid(self) -> None:
        for path in REPO_ROOT.rglob("*.json"):
            if ".git" not in path.parts:
                json.loads(path.read_text(encoding="utf-8"))

    def test_release_docs_exist_and_markdown_fences_are_balanced(self) -> None:
        required = [
            REPO_ROOT / "LICENSE",
            REPO_ROOT / "SECURITY.md",
            TOOL_ROOT / "CHANGELOG.md",
            REPO_ROOT / "README.zh-CN.md",
            TOOL_ROOT / "README.zh-CN.md",
        ]
        self.assertTrue(all(path.is_file() for path in required))
        for path in REPO_ROOT.rglob("*.md"):
            fences = sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.startswith("```"))
            self.assertEqual(fences % 2, 0, f"unbalanced Markdown fence in {path}")


if __name__ == "__main__":
    unittest.main()
