# Automatic snapshot setup

The checked-in hook settings require **Claude Code 2.1.139+** for exec-form `command` plus `args`. `PostCompact` was introduced in **2.1.76**. The script requires Python 3.8+ and only the standard library.

Settings run the existing **company-approved `python` interpreter** on PATH. If the approved executable is named `python3` or is an absolute `python.exe` path, change the hook `command` to that executable in local settings. Do not install another interpreter, change provider/authentication configuration, bypass PowerShell execution policy, or override managed policy to enable it.

`PostCompact` saves the generated `compact_summary` to the current session's gitignored `COMPACTION.md`, capped at 24 KiB. It does not open `transcript_path` or make another model call. Common credential patterns are redacted; this is not a guarantee that sensitive company information is absent.

`SessionStart` handles `startup`, `resume`, and `compact` only. Its output is a short pointer for the current session, never the file contents or another session's state. A `compact` pointer can arrive before `PostCompact` has saved the file. A new conversation needs the user to select an earlier handoff path explicitly.

Python payload tests check this script's contract. They do not establish that a particular installed Claude Code client emits its documented events. Inspect `/hooks`, run a small `/compact`, and verify the local file appears. Use `/finance-handoff` if the installed client does not emit `PostCompact`.

Official references, verified 2026-10-06:

- https://code.claude.com/docs/en/hooks#postcompact
- https://code.claude.com/docs/en/hooks#sessionstart
- https://code.claude.com/docs/en/hooks#command-hook-fields
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/costs#manage-context-proactively

More implementation detail: [local hook README](../../../hooks/README.md).
