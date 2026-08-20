# Security Boundaries

The team distribution is intended for local, read-only Power BI semantic-model inspection.

- Do not store API keys, tokens, passwords, PBIX files, or extracted business metadata in this toolkit folder.
- `.env` contains only local executable and output paths.
- Metadata output defaults to `%USERPROFILE%\PowerBI-Evidence`.
- The TE2 wrapper allowlists only `te2\readonly\export_model_inventory.csx` and does not invoke deploy, save, build, processing, or refresh switches.
- DAX execution requires an explicit query file and records its SHA-256 hash.
- TE2 and DAX Studio executables must have a valid Authenticode signature from their expected publisher before each wrapper invocation.
- Zero-touch setup must not request administrator credentials. TE2 uses only a verified user-scope silent WinGet portable path (with agreement acceptance and dependencies skipped only after the required runtime is verified) or a hash-pinned official portable ZIP. DAX Studio uses its official portable ZIP under `%LOCALAPPDATA%`. The toolkit never answers, bypasses, disables, or weakens UAC/security controls and stops on explicit organizational-policy blocks.
- Git is not a runtime dependency. `TOOLKIT_ENFORCE_GIT_CLEAN=1` exists only for development checkouts.

## Unsigned-download release gate

This release candidate is unsigned. Browser or SharePoint downloads may preserve Mark-of-the-Web, causing `RemoteSigned` or stricter policy to reject the launcher before it executes. Do not use `Unblock-File`, remove `Zone.Identifier`, lower execution policy, or otherwise bypass that control. A blocked marked ZIP is a rollout failure that requires trusted signing or an approved trusted distribution channel.

No supported setup path requires elevation. If Windows displays a UAC prompt, cancel it and report the test as failed.
