"""Deterministic contract checks for Claude Code's local checkpoint hook."""

import ast
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / ".claude" / "hooks" / "save_compaction.py"
SPEC = importlib.util.spec_from_file_location("save_compaction", HOOK_PATH)
HOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOOK)


class HandoffHookTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name) / "project"
        self.root.mkdir()
        self.payload = {
            "hook_event_name": "PostCompact", "session_id": "test-session_123",
            "trigger": "manual", "compact_summary": "Verified schema from DESCRIBE.\nNext: validate grain.",
            "cwd": "/must/not/use", "transcript_path": "/must/not/read/transcript.jsonl"
        }

    def tearDown(self):
        self.scratch.cleanup()

    def snapshot(self):
        return self.root / ".claude/state/sessions/test-session_123/COMPACTION.md"

    def test_snapshot_is_atomic_and_only_uses_summary(self):
        HOOK.handle_event(self.payload, self.root)
        content = self.snapshot().read_text(encoding="utf-8")
        self.assertIn("Next: validate grain", content)
        self.assertNotIn("/must/not", content)
        self.assertEqual(list(self.snapshot().parent.glob("*.tmp")), [])
        self.payload["compact_summary"] = "Updated next action."
        HOOK.handle_event(self.payload, self.root)
        self.assertIn("Updated next action", self.snapshot().read_text())
        self.assertNotIn("validate grain", self.snapshot().read_text())

    def test_rejects_absent_or_empty_summary_without_creating_state(self):
        for missing in (None, "", " ", [], {}):
            with self.subTest(summary=missing):
                self.payload["compact_summary"] = missing
                with self.assertRaises(HOOK.HookInputError):
                    HOOK.handle_event(self.payload, self.root)
        self.assertFalse((self.root / ".claude").exists())

    def test_rejects_path_like_session_ids(self):
        for session_id in ("../outside", "/absolute", "a/b", "a\\b", "", "x" * 129, None):
            with self.subTest(session_id=session_id):
                self.payload["session_id"] = session_id
                with self.assertRaises(HOOK.HookInputError):
                    HOOK.handle_event(self.payload, self.root)
        self.assertFalse((self.root / ".claude").exists())

    def test_rejects_symlink_at_any_state_directory(self):
        outside = Path(self.scratch.name) / "outside"
        outside.mkdir()
        components = (".claude", "state", "sessions", "test-session_123")
        for index, component in enumerate(components):
            with self.subTest(component=component):
                project = self.root / str(index)
                project.mkdir()
                parent = project
                for earlier in components[:index]:
                    parent = parent / earlier
                    parent.mkdir()
                try:
                    (parent / component).symlink_to(outside, target_is_directory=True)
                except (OSError, NotImplementedError):
                    self.skipTest("Symlink creation is unavailable on this platform")
                with self.assertRaises(HOOK.HookInputError):
                    HOOK.handle_event(self.payload, project)
        self.assertEqual(list(outside.iterdir()), [])

    def test_rejects_symlink_snapshot_and_non_directory_state(self):
        directory = HOOK._session_directory(self.root, self.payload["session_id"], create=True)
        outside = Path(self.scratch.name) / "outside.md"
        outside.write_text("Leave unchanged")
        try:
            (directory / "COMPACTION.md").symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation is unavailable on this platform")
        with self.assertRaises(HOOK.HookInputError):
            HOOK.handle_event(self.payload, self.root)
        self.assertEqual(outside.read_text(), "Leave unchanged")

    def test_redacts_common_secret_forms_and_bounds_utf8(self):
        summary = (
            "api_key=\"super-secret\"\npassword: 'do-not-save'\n"
            "Bearer abc.def.123\ndapi" + "a" * 32 + "\n"
            "-----BEGIN PRIVATE KEY-----\nprivate-key-content\n-----END PRIVATE KEY-----\n"
            + "é" * (HOOK.MAX_SUMMARY_BYTES * 2)
        )
        self.payload["compact_summary"] = summary
        HOOK.handle_event(self.payload, self.root)
        content = self.snapshot().read_text(encoding="utf-8")
        for secret in ("super-secret", "do-not-save", "abc.def.123", "dapi" + "a" * 32, "private-key-content"):
            self.assertNotIn(secret, content)
        self.assertIn("[REDACTED]", content)
        self.assertIn("Snapshot truncated", content)
        self.assertLess(len(content.encode("utf-8")), HOOK.MAX_SUMMARY_BYTES + 1024)

    def test_validates_event_trigger_and_source(self):
        for event in (None, "PreCompact", "Stop", "SessionEnd"):
            with self.subTest(event=event):
                bad = dict(self.payload, hook_event_name=event)
                with self.assertRaises(HOOK.HookInputError):
                    HOOK.handle_event(bad, self.root)
        with self.assertRaises(HOOK.HookInputError):
            HOOK.handle_event(dict(self.payload, trigger="plugin"), self.root)
        for source in (None, "clear", "fork", "something-else"):
            with self.subTest(source=source):
                with self.assertRaises(HOOK.HookInputError):
                    HOOK.handle_event({"hook_event_name": "SessionStart", "session_id": "valid", "source": source}, self.root)

    def test_pointer_is_bounded_and_only_for_current_session(self):
        HOOK.handle_event(self.payload, self.root)
        resume = {"hook_event_name": "SessionStart", "session_id": "test-session_123", "source": "resume"}
        output = HOOK.handle_event(resume, self.root)
        context = output["hookSpecificOutput"]["additionalContext"]
        self.assertIn("COMPACTION.md", context)
        self.assertNotIn("Verified schema", context)
        self.assertLess(len(context), 512)
        self.assertIsNone(HOOK.handle_event(dict(resume, session_id="another-session"), self.root))
        compact = HOOK.handle_event(dict(resume, session_id="new-session", source="compact"), self.root)
        self.assertIn("saved when PostCompact", compact["hookSpecificOutput"]["additionalContext"])
        self.assertFalse((self.root / ".claude/state/sessions/new-session").exists())

    def test_no_process_or_network_dependencies_and_settings_contract(self):
        tree = ast.parse(HOOK_PATH.read_text(encoding="utf-8"))
        imported = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.extend(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                imported.append(node.module.split(".")[0])
        self.assertFalse(set(imported) & {"subprocess", "requests", "urllib", "http", "socket"})
        self.assertFalse(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                             and isinstance(node.func.value, ast.Name) and node.func.value.id == "os"
                             and node.func.attr in {"system", "popen", "spawnl", "spawnv"}
                             for node in ast.walk(tree)))
        settings = json.loads((ROOT / ".claude/settings.json").read_text())
        self.assertEqual(set(settings["hooks"]), {"PostCompact", "SessionStart"})
        for entries in settings["hooks"].values():
            for entry in entries:
                for handler in entry["hooks"]:
                    self.assertEqual(handler["type"], "command")
                    self.assertEqual(handler["command"], "python")
                    self.assertEqual(handler["args"], ["${CLAUDE_PROJECT_DIR}/.claude/hooks/save_compaction.py"])


if __name__ == "__main__":
    unittest.main()
