# Local context checkpoints

`save_compaction.py` uses only Python's standard library. It reads the documented hook payload from stdin. It does not read the conversation transcript, run a subprocess, call an API/model, install tools, change authentication, or change PowerShell execution policy.

- `PostCompact`: saves Claude Code's existing `compact_summary` atomically to `.claude/state/sessions/<session-id>/COMPACTION.md`. The summary body is bounded at 24 KiB; common credential patterns are redacted. This records a recovery snapshot and makes no additional model request. The built-in compaction itself uses model tokens.
- `SessionStart` on `startup`, `resume`, or `compact`: returns a short pointer to the current session's local checkpoint files. It never inserts their contents or another session's state automatically. On compaction, the pointer may arrive before the snapshot has been written.
- `/finance-handoff`: creates or updates a much smaller reviewed `HANDOFF.md` with evidence references and the next action. In a fresh conversation, select that exact path to resume an earlier investigation.

Keep local state gitignored and internal. A generated summary can contain sensitive business information even after credential-pattern redaction. This hook cannot guarantee full redaction. The summary is model-generated, so recheck financial claims against source artifacts. Saving a file alone does not shrink context: use `/compact` to continue the same investigation or `/clear` for unrelated work.

The committed `.claude/settings.json` uses hook exec form (`command` plus `args`). It requires Claude Code **2.1.139 or later**; `PostCompact` itself was added in **2.1.76**. The configured interpreter is `python`: on Windows use the existing company-approved `python.exe` on PATH. On Linux/macOS, if the approved interpreter is named `python3`, change only each hook's `command` to `python3` in local settings; an absolute approved interpreter path also works. No dependency installation is required. Do not bypass a managed policy that prevents project hooks or skills.

Merge these hook entries with existing settings rather than replacing permission, provider, or managed configuration. Inspect `/hooks` and run a small manual `/compact` to verify the installed Claude Code client emits `PostCompact` and creates the current session's snapshot. Keep `/finance-handoff` as the explicit fallback if a client does not emit the hook. Synthetic tests validate the script, not the installed Claude Code lifecycle.

Source references, verified 2026-10-06:

- [Skills discovery and progressive loading](https://code.claude.com/docs/en/skills)
- [PostCompact payload](https://code.claude.com/docs/en/hooks#postcompact)
- [SessionStart payload and additional context](https://code.claude.com/docs/en/hooks#sessionstart)
- [Hook exec form and path placeholders](https://code.claude.com/docs/en/hooks#command-hook-fields)
- [Official release history](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md)
- [Token usage and compaction](https://code.claude.com/docs/en/costs#manage-context-proactively)
- [Gateway prompt-caching compatibility](https://code.claude.com/docs/en/llm-gateway-protocol#feature-pass-through)

`PreCompact` is not configured here: it has no `compact_summary` and does not support a prompt or agent hook. Creating another model call from a shell hook would add cost and configuration rather than reuse the summary Claude already generates.
