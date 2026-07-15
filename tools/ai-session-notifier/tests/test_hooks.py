from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_ROOT.parents[1]
CODEX_HOOK = TOOL_ROOT / "codex-plugin" / "scripts" / "codex-notify.sh"
CLAUDE_HOOK = TOOL_ROOT / "claude-code-plugin" / "bin" / "ai-session-notify"
INSTALLER = TOOL_ROOT / "scripts" / "install.sh"
UNINSTALLER = TOOL_ROOT / "scripts" / "uninstall.sh"


@unittest.skipIf(os.name == "nt", "Unix shell adapter tests run on macOS and Linux")
class HookTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.root / "home"),
                "CODEX_HOME": str(self.root / "codex"),
                "AI_SESSION_NOTIFIER_CONFIG_DIR": str(self.root / "config"),
                "AI_SESSION_NOTIFIER_DATA_DIR": str(self.root / "data"),
                "AI_SESSION_NOTIFIER_DRY_RUN": "1",
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def invoke(self, command: Path, payload: dict[str, object]) -> None:
        subprocess.run(
            [str(command)],
            input=json.dumps(payload),
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        )

    def events(self) -> list[dict[str, object]]:
        path = self.root / "data" / "events.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]

    def test_adapters_write_private_redacted_events_and_compact_routes(self) -> None:
        if shutil.which("zsh"):
            self.invoke(
                CODEX_HOOK,
                {
                    "hook_event_name": "PermissionRequest",
                    "threadId": "codex-session",
                    "source": "vscode",
                    "cwd": "/tmp/codex-project",
                    "last_assistant_message": "private codex text",
                },
            )
        self.invoke(
            CLAUDE_HOOK,
            {
                "hook_event_name": "Notification",
                "notification_type": "idle_prompt",
                "session_id": "claude-session",
                "cwd": "/tmp/claude-project",
                "last_assistant_message": "private claude text",
            },
        )

        events = self.events()
        self.assertTrue(events)
        self.assertTrue(all(event["lastAssistantMessage"] == "" for event in events))
        self.assertTrue(all(event["schemaVersion"] == 1 for event in events))
        registry = json.loads((self.root / "data" / "sessions.json").read_text(encoding="utf-8"))
        self.assertIn("claude-code:claude-session", registry["sessions"])
        if shutil.which("zsh"):
            self.assertIn("codex:codex-session", registry["sessions"])
        self.assertFalse((self.root / "codex" / "hooks" / "last-payload.json").exists())
        self.assertFalse((self.root / "data" / "debug" / "last-payload.json").exists())
        if os.name != "nt":
            self.assertEqual((self.root / "data" / "events.jsonl").stat().st_mode & 0o777, 0o600)

    def test_concurrent_claude_events_remain_valid_jsonl(self) -> None:
        def send(index: int) -> None:
            self.invoke(
                CLAUDE_HOOK,
                {
                    "hook_event_name": "Notification",
                    "notification_type": "permission_prompt",
                    "session_id": f"session-{index}",
                    "cwd": f"/tmp/project-{index}",
                },
            )

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(send, range(20)))

        self.assertEqual(len(self.events()), 20)
        registry = json.loads((self.root / "data" / "sessions.json").read_text(encoding="utf-8"))
        self.assertEqual(len(registry["sessions"]), 20)

    @unittest.skipUnless(shutil.which("zsh"), "Codex installer requires zsh")
    def test_install_and_uninstall_preserve_unrelated_codex_hooks(self) -> None:
        codex_home = self.root / "codex"
        codex_home.mkdir(parents=True)
        hooks_path = codex_home / "hooks.json"
        hooks_path.write_text(
            json.dumps(
                {
                    "hooks": {
                        "Stop": [{"hooks": [{"type": "command", "command": "/tmp/unrelated.sh"}]}],
                        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/tmp/prompt.sh"}]}],
                    }
                }
            ),
            encoding="utf-8",
        )
        subprocess.run([str(INSTALLER), "--codex"], env=self.env, text=True, capture_output=True, check=True)
        self.assertTrue((self.root / "home" / ".local" / "bin" / "ai-session-notifier").is_file())
        self.assertTrue((self.root / "home" / ".local" / "bin" / "ai-session-report").is_file())
        installed = json.loads(hooks_path.read_text(encoding="utf-8"))
        stop_commands = [hook["command"] for entry in installed["hooks"]["Stop"] for hook in entry["hooks"]]
        self.assertIn("/tmp/unrelated.sh", stop_commands)
        self.assertTrue(any(command.endswith("codex-notify.sh") for command in stop_commands))
        self.assertIn("PermissionRequest", installed["hooks"])
        self.assertIn("UserPromptSubmit", installed["hooks"])

        subprocess.run([str(UNINSTALLER), "--codex"], env=self.env, text=True, capture_output=True, check=True)
        removed = json.loads(hooks_path.read_text(encoding="utf-8"))
        self.assertEqual(removed["hooks"]["Stop"][0]["hooks"][0]["command"], "/tmp/unrelated.sh")
        self.assertIn("UserPromptSubmit", removed["hooks"])
        self.assertNotIn("PermissionRequest", removed["hooks"])

    def test_install_dry_run_does_not_write(self) -> None:
        result = subprocess.run(
            [str(INSTALLER), "--codex", "--dry-run"],
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("no files changed", result.stdout)
        self.assertFalse((self.root / "codex" / "hooks.json").exists())

    @unittest.skipUnless(shutil.which("zsh"), "Uninstaller requires zsh")
    def test_purge_refuses_to_delete_home_directory(self) -> None:
        unsafe_env = self.env.copy()
        unsafe_env["AI_SESSION_NOTIFIER_CONFIG_DIR"] = unsafe_env["HOME"]
        Path(unsafe_env["HOME"]).mkdir(parents=True)
        result = subprocess.run(
            [str(UNINSTALLER), "--codex", "--purge"],
            env=unsafe_env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("Refusing unsafe purge path", result.stderr)
        self.assertTrue(Path(unsafe_env["HOME"]).is_dir())


if __name__ == "__main__":
    unittest.main()
