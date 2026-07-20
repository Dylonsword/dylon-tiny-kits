from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_ROOT.parents[1]
CODEX_HOOK = TOOL_ROOT / "codex-plugin" / "scripts" / "codex-notify.sh"
CLAUDE_HOOK = TOOL_ROOT / "claude-code-plugin" / "bin" / "ai-session-notify"
KIMI_HOOK = TOOL_ROOT / "kimi-code-plugin" / "hooks" / "ai-session-notify"
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
                "KIMI_CODE_HOME": str(self.root / "kimi"),
                "AI_SESSION_NOTIFIER_CONFIG_DIR": str(self.root / "config"),
                "AI_SESSION_NOTIFIER_DATA_DIR": str(self.root / "data"),
                "AI_SESSION_NOTIFIER_DRY_RUN": "1",
                "AI_SESSION_NOTIFIER_LOCALE": "en",
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

    def write_codex_transcript(self, name: str, reviewer: str) -> Path:
        path = self.root / "codex" / "sessions" / "2026" / "07" / "17" / f"{name}.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "timestamp": "2026-07-17T00:00:00Z",
                    "type": "turn_context",
                    "payload": {
                        "approval_policy": "on-request",
                        "approvals_reviewer": reviewer,
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return path

    @unittest.skipUnless(shutil.which("zsh"), "Codex hook requires zsh")
    def test_codex_smart_permission_mode_suppresses_only_automatic_review(self) -> None:
        auto_transcript = self.write_codex_transcript("auto-review", "auto_review")
        self.invoke(
            CODEX_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "threadId": "codex-auto-review",
                "transcript_path": str(auto_transcript),
                "permission_mode": "default",
                "cwd": "/tmp/codex-auto-review",
            },
        )

        manual_transcript = self.write_codex_transcript("manual-review", "user")
        self.invoke(
            CODEX_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "threadId": "codex-manual-review",
                "transcript_path": str(manual_transcript),
                "permission_mode": "default",
                "cwd": "/tmp/codex-manual-review",
            },
        )
        self.invoke(
            CODEX_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "threadId": "codex-future-payload",
                "approval_context": {"approvals_reviewer": "guardian_subagent"},
                "permission_mode": "default",
                "cwd": "/tmp/codex-future-payload",
            },
        )
        self.invoke(
            CODEX_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "threadId": "codex-unknown-reviewer",
                "permission_mode": "default",
                "cwd": "/tmp/codex-unknown-reviewer",
            },
        )

        events = {str(event["threadId"]): event for event in self.events()}
        self.assertTrue(events["codex-auto-review"]["suppressed"])
        self.assertEqual(
            events["codex-auto-review"]["suppressionReason"],
            "approval_reviewer:auto_review",
        )
        self.assertEqual(events["codex-auto-review"]["approvalReviewer"], "auto_review")
        self.assertFalse(events["codex-manual-review"]["suppressed"])
        self.assertTrue(events["codex-future-payload"]["suppressed"])
        self.assertFalse(events["codex-unknown-reviewer"]["suppressed"])

    @unittest.skipUnless(shutil.which("zsh"), "Codex hook requires zsh")
    def test_codex_permission_notification_mode_can_override_smart_detection(self) -> None:
        self.env["AI_SESSION_NOTIFIER_PERMISSION_MODE"] = "notify"
        self.invoke(
            CODEX_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "threadId": "codex-notify-override",
                "approvals_reviewer": "auto_review",
                "permission_mode": "default",
                "cwd": "/tmp/codex-notify-override",
            },
        )

        event = self.events()[0]
        self.assertFalse(event["suppressed"])

    def test_claude_and_kimi_keep_real_auto_mode_permission_prompts_visible(self) -> None:
        self.invoke(
            CLAUDE_HOOK,
            {
                "hook_event_name": "Notification",
                "notification_type": "permission_prompt",
                "permission_mode": "auto",
                "session_id": "claude-auto-fallback",
                "cwd": "/tmp/claude-auto-fallback",
            },
        )
        self.invoke(
            KIMI_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "permission_mode": "auto",
                "session_id": "kimi-auto-fallback",
                "cwd": "/tmp/kimi-auto-fallback",
            },
        )

        self.assertTrue(all(not event["suppressed"] for event in self.events()))

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
        self.invoke(
            KIMI_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "session_id": "kimi-session",
                "cwd": "/tmp/kimi-project",
                "message": "private kimi text",
            },
        )

        events = self.events()
        self.assertTrue(events)
        self.assertTrue(all(event["lastAssistantMessage"] == "" for event in events))
        self.assertTrue(all(event["schemaVersion"] == 1 for event in events))
        registry = json.loads((self.root / "data" / "sessions.json").read_text(encoding="utf-8"))
        self.assertIn("claude-code:claude-session", registry["sessions"])
        self.assertIn("kimi-code:kimi-session", registry["sessions"])
        if shutil.which("zsh"):
            self.assertIn("codex:codex-session", registry["sessions"])
        self.assertFalse((self.root / "codex" / "hooks" / "last-payload.json").exists())
        self.assertFalse((self.root / "data" / "debug" / "last-payload.json").exists())
        if os.name != "nt":
            self.assertEqual((self.root / "data" / "events.jsonl").stat().st_mode & 0o777, 0o600)

    def test_kimi_events_keep_stop_turn_scoped_and_classify_failures(self) -> None:
        cases = [
            ({"hook_event_name": "Stop", "session_id": "kimi-stop", "cwd": "/tmp/kimi"}, "stop"),
            (
                {"hook_event_name": "StopFailure", "session_id": "kimi-failure", "cwd": "/tmp/kimi"},
                "error",
            ),
            (
                {
                    "hook_event_name": "Notification",
                    "notification_type": "task.completed",
                    "session_id": "kimi-background",
                    "cwd": "/tmp/kimi",
                },
                "completion",
            ),
        ]
        for payload, _category in cases:
            self.invoke(KIMI_HOOK, payload)

        events = self.events()
        self.assertEqual([event["category"] for event in events], [item[1] for item in cases])
        stop_event = events[0]
        self.assertIn("turn stopped", str(stop_event["title"]).lower())
        self.assertNotIn("task completed", str(stop_event["title"]).lower())
        self.assertNotIn("task finished", str(stop_event["message"]).lower())

    def test_notification_locale_can_be_forced_to_simplified_chinese(self) -> None:
        self.env["AI_SESSION_NOTIFIER_LOCALE"] = "zh-CN"
        if shutil.which("zsh"):
            self.invoke(
                CODEX_HOOK,
                {
                    "hook_event_name": "PermissionRequest",
                    "threadId": "codex-zh-cn",
                    "cwd": "/tmp/codex-zh-cn",
                },
            )
        self.invoke(
            CLAUDE_HOOK,
            {
                "hook_event_name": "Notification",
                "notification_type": "permission_prompt",
                "session_id": "claude-zh-cn",
                "cwd": "/tmp/claude-zh-cn",
            },
        )
        self.invoke(
            KIMI_HOOK,
            {
                "hook_event_name": "PermissionRequest",
                "session_id": "kimi-zh-cn",
                "cwd": "/tmp/kimi-zh-cn",
            },
        )

        events_by_tool = {str(event["tool"]): event for event in self.events()}
        self.assertIn("权限", str(events_by_tool["Claude Code"]["title"]))
        self.assertIn("%E8%BF%94", str(events_by_tool["Claude Code"]["targetUrl"]))
        self.assertIn("权限", str(events_by_tool["Kimi Code"]["title"]))
        if shutil.which("zsh"):
            self.assertIn("权限", str(events_by_tool["Codex"]["title"]))

    def test_traditional_chinese_locale_falls_back_to_english(self) -> None:
        self.env["AI_SESSION_NOTIFIER_LOCALE"] = "zh-TW"
        self.invoke(
            KIMI_HOOK,
            {
                "hook_event_name": "Stop",
                "session_id": "kimi-zh-tw",
                "cwd": "/tmp/kimi-zh-tw",
            },
        )

        event = self.events()[0]
        self.assertIn("turn stopped", str(event["title"]).lower())

    def test_kimi_macos_banner_routes_through_workspace_callback(self) -> None:
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        capture = self.root / "terminal-notifier.args"

        fake_uname = fake_bin / "uname"
        fake_uname.write_text("#!/bin/sh\nprintf 'Darwin\\n'\n", encoding="utf-8")
        fake_uname.chmod(0o700)

        fake_notifier = fake_bin / "terminal-notifier"
        fake_notifier.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$AI_SESSION_NOTIFIER_CAPTURE\"\n",
            encoding="utf-8",
        )
        fake_notifier.chmod(0o700)

        config_dir = self.root / "config"
        config_dir.mkdir(parents=True, exist_ok=True)
        (config_dir / "config.json").write_text(
            json.dumps(
                {
                    "notifications": {
                        "dialogs": False,
                        "ignoreDnD": False,
                        "sound": False,
                    }
                }
            ),
            encoding="utf-8",
        )

        self.env.pop("AI_SESSION_NOTIFIER_DRY_RUN")
        self.env["PATH"] = f"{fake_bin}{os.pathsep}{self.env['PATH']}"
        self.env["AI_SESSION_NOTIFIER_CAPTURE"] = str(capture)
        self.env["__CFBundleIdentifier"] = "com.microsoft.VSCode"
        self.invoke(
            KIMI_HOOK,
            {
                "hook_event_name": "Stop",
                "session_id": "kimi-window-route",
                "cwd": "/tmp/kimi-target-workspace",
            },
        )

        notifier_args = capture.read_text(encoding="utf-8").splitlines()
        self.assertIn("-execute", notifier_args)
        execute_command = notifier_args[notifier_args.index("-execute") + 1]
        self.assertIn("--open-target", execute_command)
        self.assertIn("/tmp/kimi-target-workspace", execute_command)
        self.assertNotIn("-activate", notifier_args)

    @unittest.skipUnless(sys.platform == "darwin", "AppleScript callback runs only on macOS")
    def test_kimi_workspace_callback_applescript_compiles(self) -> None:
        additions_probe = subprocess.run(
            ["/usr/bin/osascript", "-e", 'do shell script "true"'],
            text=True,
            capture_output=True,
            check=False,
        )
        if additions_probe.returncode != 0:
            self.skipTest("Standard Additions are unavailable in this sandbox")

        script = KIMI_HOOK.read_text(encoding="utf-8")
        blocks = re.findall(r"<<'OSA'[^\n]*\n(.*?)\nOSA", script, flags=re.DOTALL)
        self.assertEqual(len(blocks), 2)
        for index, block in enumerate(blocks):
            result = subprocess.run(
                ["/usr/bin/osacompile", "-o", str(self.root / f"kimi-{index}.scpt")],
                input=block,
                env=self.env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

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

    @unittest.skipUnless(shutil.which("zsh"), "Unified installer requires zsh")
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
