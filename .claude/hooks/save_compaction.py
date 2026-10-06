#!/usr/bin/env python3
"""Save a bounded local Claude Code compaction snapshot without another model call.

Reads hook JSON from stdin only. It never opens transcript_path, calls a model,
starts a process, changes authentication, or sends data over the network.
"""

import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from datetime import datetime, timezone


MAX_INPUT_BYTES = 512 * 1024
MAX_SUMMARY_BYTES = 24 * 1024
SESSION_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
SUPPORTED_EVENTS = {"PostCompact", "SessionStart"}
SUPPORTED_SOURCES = {"startup", "resume", "compact"}
SUPPORTED_TRIGGERS = {"manual", "auto"}
# These patterns catch recognizable credentials, not all sensitive information.
SECRET_TOKEN = re.compile(
    r"\b(?:dapi[0-9a-fA-F]{16,}|gh[pousr]_[A-Za-z0-9_]{16,}|"
    r"github_pat_[A-Za-z0-9_]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|"
    r"AKIA[A-Z0-9]{16})\b"
)
SECRET_ASSIGNMENT = re.compile(
    r"(?i)(\b(?:api[_ -]?key|access[_ -]?token|auth[_ -]?token|"
    r"client[_ -]?secret|password|authorization)\b\s*[:=]\s*)"
    r"(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"
)
BEARER = re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+")
PRIVATE_KEY = re.compile(
    r"-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?"
    r"-----END [^-\r\n]*PRIVATE KEY-----", re.DOTALL
)


class HookInputError(ValueError):
    """Reject invalid event data or an unsafe local path."""


def _link_like(path):
    """Reject POSIX symlinks and Windows reparse points, including junctions."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISLNK(info.st_mode) or bool(
        getattr(info, "st_file_attributes", 0)
        & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    )


def _inside_root(path, root):
    try:
        path.resolve().relative_to(root)
    except ValueError as error:
        raise HookInputError("State path escapes the project root") from error


def _session_directory(project_root, session_id, create=False):
    if not isinstance(session_id, str) or not SESSION_ID.fullmatch(session_id):
        raise HookInputError("Invalid session_id")
    root = Path(project_root).resolve(strict=True)
    if not root.is_dir():
        raise HookInputError("Project root is not a directory")
    current = root
    for component in (".claude", "state", "sessions", session_id):
        current = current / component
        if _link_like(current):
            raise HookInputError("State path contains a symlink or junction")
        _inside_root(current, root)
        if current.exists() and not current.is_dir():
            raise HookInputError("State path component is not a directory")
        if create:
            current.mkdir(exist_ok=True)
            if _link_like(current):
                raise HookInputError("State path changed to a symlink or junction")
            _inside_root(current, root)
    return current


def redact_summary(summary):
    """Remove common credential forms; company-data review remains necessary."""
    summary = PRIVATE_KEY.sub("[REDACTED PRIVATE KEY]", summary)
    summary = SECRET_TOKEN.sub("[REDACTED TOKEN]", summary)
    summary = BEARER.sub("Bearer [REDACTED]", summary)
    summary = SECRET_ASSIGNMENT.sub(r"\1[REDACTED]", summary)
    # Keep newlines/tabs, but discard terminal control characters.
    return "".join(c for c in summary if c in "\n\t" or ord(c) >= 32).replace("\x7f", "")


def bounded_summary(summary):
    summary = redact_summary(summary).strip()
    encoded = summary.encode("utf-8")
    if len(encoded) <= MAX_SUMMARY_BYTES:
        return summary
    truncated = encoded[:MAX_SUMMARY_BYTES].decode("utf-8", errors="ignore")
    # Avoid a partial final line where possible.
    if "\n" in truncated:
        truncated = truncated.rsplit("\n", 1)[0]
    return truncated + "\n\n[Snapshot truncated at 24 KiB; consult selected source artifacts.]"


def _safe_file(path):
    if _link_like(path):
        raise HookInputError("State file is a symlink or junction")
    if path.exists() and not path.is_file():
        raise HookInputError("State target is not a regular file")


def save_snapshot(payload, project_root):
    summary = payload.get("compact_summary")
    if not isinstance(summary, str) or not summary.strip():
        raise HookInputError("PostCompact did not provide compact_summary")
    if payload.get("trigger") not in SUPPORTED_TRIGGERS:
        raise HookInputError("Invalid compaction trigger")
    directory = _session_directory(project_root, payload.get("session_id"), create=True)
    destination = directory / "COMPACTION.md"
    _safe_file(destination)
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    content = (
        "# Automatic compaction snapshot\n\n"
        "Source: Claude Code built-in compaction; this is not verified evidence.\n"
        "Stored locally; do not commit or push this file.\n"
        "Common credential patterns are redacted; sensitive company data may remain.\n"
        "Saved: " + timestamp + "\n"
        "Trigger: " + payload["trigger"] + "\n\n"
        + bounded_summary(summary) + "\n"
    )
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=directory,
            prefix=".compaction-", suffix=".tmp", delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        # Revalidate the entire destination immediately before atomic replacement.
        _session_directory(project_root, payload["session_id"], create=False)
        _safe_file(destination)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return destination


def session_pointer(payload, project_root):
    source = payload.get("source")
    if source not in SUPPORTED_SOURCES:
        raise HookInputError("Unsupported SessionStart source")
    directory = _session_directory(project_root, payload.get("session_id"))
    names = []
    for filename in ("HANDOFF.md", "COMPACTION.md"):
        target = directory / filename
        _safe_file(target)
        if target.is_file():
            names.append(filename)
    # SessionStart(compact) may run before PostCompact writes the first snapshot.
    if source == "compact" and "COMPACTION.md" not in names:
        names.append("COMPACTION.md (saved when PostCompact completes)")
    if not names:
        return None
    relative = ".claude/state/sessions/" + payload["session_id"] + "/"
    context = (
        "Current-session local checkpoint directory: " + relative + ". "
        "Files: " + ", ".join(names) + ". "
        "Read only if useful. Automatic summaries are unverified. "
        "Do not load other sessions or commit local state."
    )
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}


def handle_event(payload, project_root):
    if not isinstance(payload, dict):
        raise HookInputError("Hook payload must be an object")
    event = payload.get("hook_event_name")
    if event not in SUPPORTED_EVENTS:
        raise HookInputError("Unsupported hook event")
    if event == "PostCompact":
        save_snapshot(payload, project_root)
        return None
    return session_pointer(payload, project_root)


def main():
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(raw) > MAX_INPUT_BYTES:
            raise HookInputError("Hook input exceeds 512 KiB")
        payload = json.loads(raw)
        project_root = os.environ.get("CLAUDE_PROJECT_DIR")
        if not project_root:
            raise HookInputError("CLAUDE_PROJECT_DIR is missing")
        # Never trust the hook payload's cwd or transcript_path as a save location.
        expected_root = Path(__file__).resolve().parents[2]
        if Path(project_root).resolve(strict=True) != expected_root:
            raise HookInputError("Project root does not match this hook's repository")
        output = handle_event(payload, project_root)
        if output is not None:
            print(json.dumps(output, ensure_ascii=True))
    except (HookInputError, OSError, ValueError, TypeError):
        # Do not leak input content and do not block the user's compaction.
        print("Local compaction checkpoint was skipped: invalid input or unavailable state path.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
