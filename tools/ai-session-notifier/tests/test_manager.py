from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_ROOT.parents[1]
MANAGER = TOOL_ROOT / "scripts" / "ai-session-notifier"
REPORT = TOOL_ROOT / "scripts" / "ai-session-report"


class ManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.root / "home"),
                "CODEX_HOME": str(self.root / "codex"),
                "KIMI_CODE_HOME": str(self.root / "kimi"),
                "AI_SESSION_NOTIFIER_CONFIG_DIR": str(self.root / "config"),
                "AI_SESSION_NOTIFIER_DATA_DIR": str(self.root / "data"),
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_manager(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(MANAGER), *args],
            env=self.env,
            text=True,
            capture_output=True,
            check=check,
        )

    def test_init_creates_private_versioned_config(self) -> None:
        result = self.run_manager("init", "--json")
        payload = json.loads(result.stdout)
        config_path = self.root / "config" / "config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))

        self.assertTrue(payload["changed"])
        self.assertEqual(config["version"], 2)
        self.assertEqual(config["notifications"]["locale"], "auto")
        self.assertEqual(config["noise"]["permissionMode"], "smart")
        self.assertFalse(config["ledger"]["includeMessageExcerpt"])
        self.assertFalse(config["debug"]["saveRawPayload"])
        self.assertTrue(all("version" not in value for value in config.values() if isinstance(value, dict)))
        if os.name != "nt":
            self.assertEqual(config_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(config_path.parent.stat().st_mode & 0o777, 0o700)

    def test_init_migrates_compact_session_registry(self) -> None:
        data_dir = self.root / "data"
        data_dir.mkdir(parents=True)
        legacy = data_dir / "session-registry.jsonl"
        records = [
            {"timestamp": "2026-01-01T00:00:00Z", "tool": "Codex", "threadId": "one", "cwd": "/a"},
            {"timestamp": "2026-01-02T00:00:00Z", "tool": "Codex", "threadId": "one", "cwd": "/b"},
            {"timestamp": "2026-01-03T00:00:00Z", "tool": "Claude Code", "threadId": "two", "cwd": "/c"},
        ]
        legacy.write_text("".join(json.dumps(item) + "\n" for item in records), encoding="utf-8")

        result = self.run_manager("init", "--json")
        payload = json.loads(result.stdout)
        registry = json.loads((data_dir / "sessions.json").read_text(encoding="utf-8"))

        self.assertEqual(payload["migratedSessions"], 2)
        self.assertEqual(len(registry["sessions"]), 2)
        self.assertEqual(registry["sessions"]["codex:one"]["cwd"], "/b")
        self.assertFalse(legacy.exists())

    def test_cleanup_prunes_old_invalid_and_oversized_events(self) -> None:
        self.run_manager("init")
        events_path = self.root / "data" / "events.jsonl"
        events_path.parent.mkdir(parents=True, exist_ok=True)
        now = datetime.now(timezone.utc)
        records = [
            {"timestamp": (now - timedelta(days=60)).isoformat(), "tool": "Codex", "threadId": "old"},
            {"timestamp": now.isoformat(), "tool": "Codex", "threadId": "new-1", "message": "x" * 180},
            {"timestamp": now.isoformat(), "tool": "Codex", "threadId": "new-2", "message": "y" * 180},
        ]
        events_path.write_text(
            json.dumps(records[0]) + "\ninvalid\n" + json.dumps(records[1]) + "\n" + json.dumps(records[2]) + "\n",
            encoding="utf-8",
        )

        result = self.run_manager("cleanup", "--retention-days", "30", "--max-bytes", "300", "--json")
        payload = json.loads(result.stdout)
        kept = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(payload["eventsExpired"], 1)
        self.assertEqual(payload["invalidLinesRemoved"], 1)
        self.assertEqual(payload["eventsTrimmed"], 1)
        self.assertEqual([item["threadId"] for item in kept], ["new-2"])

    def test_init_redacts_historical_message_excerpts_by_default(self) -> None:
        data_dir = self.root / "data"
        data_dir.mkdir(parents=True)
        timestamp = datetime.now(timezone.utc).isoformat()
        (data_dir / "events.jsonl").write_text(
            json.dumps({"timestamp": timestamp, "lastAssistantMessage": "private event"}) + "\n",
            encoding="utf-8",
        )
        (data_dir / "sessions.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "sessions": {
                        "codex:test": {"timestamp": timestamp, "lastAssistantMessage": "private session"}
                    },
                }
            ),
            encoding="utf-8",
        )

        payload = json.loads(self.run_manager("init", "--json").stdout)
        event = json.loads((data_dir / "events.jsonl").read_text(encoding="utf-8"))
        registry = json.loads((data_dir / "sessions.json").read_text(encoding="utf-8"))

        self.assertEqual(payload["redactedEventExcerpts"], 1)
        self.assertEqual(payload["redactedSessionExcerpts"], 1)
        self.assertEqual(event["lastAssistantMessage"], "")
        self.assertEqual(registry["sessions"]["codex:test"]["lastAssistantMessage"], "")

    def test_status_and_report_return_machine_readable_json(self) -> None:
        self.run_manager("init")
        events_path = self.root / "data" / "events.jsonl"
        events_path.write_text(
            json.dumps(
                {
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "tool": "Codex",
                    "category": "permission",
                    "cwd": "/tmp/project",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        status = json.loads(self.run_manager("status", "--json").stdout)
        report = subprocess.run(
            [sys.executable, str(REPORT), "--file", str(events_path), "--json"],
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        )
        report_payload = json.loads(report.stdout)

        self.assertEqual(status["events"], 1)
        self.assertEqual(report_payload["total"], 1)
        self.assertEqual(report_payload["byTool"], {"Codex": 1})

    def test_status_reports_per_tool_icon_overrides(self) -> None:
        self.run_manager("init")
        codex_icon = self.root / "codex.png"
        claude_icon = self.root / "claude.png"
        kimi_icon = self.root / "kimi.png"
        codex_icon.write_bytes(b"codex")
        claude_icon.write_bytes(b"claude")
        kimi_icon.write_bytes(b"kimi")
        config_path = self.root / "config" / "config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        config["notifications"]["codexIconPath"] = str(codex_icon)
        config["notifications"]["claudeIconPath"] = str(claude_icon)
        config["notifications"]["kimiIconPath"] = str(kimi_icon)
        config_path.write_text(json.dumps(config), encoding="utf-8")

        status = json.loads(self.run_manager("status", "--json").stdout)

        self.assertEqual(status["icons"]["codex"], str(codex_icon))
        self.assertEqual(status["icons"]["claude"], str(claude_icon))
        self.assertEqual(status["icons"]["kimi"], str(kimi_icon))

    @unittest.skipIf(os.name == "nt", "Source Kimi shell adapter is exercised on Unix")
    def test_manager_can_test_kimi_adapter(self) -> None:
        result = self.run_manager("test", "--tool", "kimi", "--dry-run")
        events_path = self.root / "data" / "events.jsonl"
        event = json.loads(events_path.read_text(encoding="utf-8"))

        self.assertIn("kimi test event sent in dry-run mode", result.stdout.lower())
        self.assertEqual(event["tool"], "Kimi Code")
        self.assertEqual(event["category"], "permission")
        self.assertEqual(event["lastAssistantMessage"], "")

    def test_kimi_status_distinguishes_disabled_plugin_from_stale_managed_copy(self) -> None:
        kimi_home = Path(self.env["KIMI_CODE_HOME"])
        managed = kimi_home / "plugins" / "managed" / "ai-session-notifier"
        managed.mkdir(parents=True)
        (managed / "kimi.plugin.json").write_text(
            json.dumps({"name": "ai-session-notifier", "version": "0.5.1"}),
            encoding="utf-8",
        )
        registry = kimi_home / "plugins" / "installed.json"
        registry.write_text(
            json.dumps(
                {
                    "version": 1,
                    "plugins": [
                        {
                            "id": "ai-session-notifier",
                            "root": str(managed),
                            "enabled": False,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

        disabled = json.loads(self.run_manager("doctor", "--json", check=False).stdout)
        plugin_check = next(item for item in disabled["checks"] if item["name"] == "Kimi Code plugin")
        self.assertEqual(plugin_check["level"], "error")
        self.assertIn("disabled", plugin_check["detail"])

        registry.write_text(json.dumps({"version": 1, "plugins": []}), encoding="utf-8")
        stale = json.loads(self.run_manager("status", "--json").stdout)["kimi"]
        self.assertFalse(stale["pluginInstalled"])
        self.assertTrue(stale["managedCopyPresent"])

    def test_installed_manager_finds_runtime_claude_adapter(self) -> None:
        installed_manager = self.root / "bin" / "ai-session-notifier"
        installed_manager.parent.mkdir(parents=True)
        shutil.copy2(MANAGER, installed_manager)

        runtime_dir = self.root / "data" / "bin"
        runtime_dir.mkdir(parents=True)
        adapter_name = "ai-session-notify.ps1" if os.name == "nt" else "ai-session-notify"
        source_adapter = TOOL_ROOT / "claude-code-plugin" / "bin" / adapter_name
        runtime_adapter = runtime_dir / adapter_name
        shutil.copy2(source_adapter, runtime_adapter)
        if os.name != "nt":
            runtime_adapter.chmod(0o700)

        result = subprocess.run(
            [sys.executable, str(installed_manager), "test", "--tool", "claude", "--dry-run"],
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        )

        self.assertIn("claude test event sent in dry-run mode", result.stdout)
        self.assertTrue((self.root / "data" / "events.jsonl").is_file())


if __name__ == "__main__":
    unittest.main()
