# Brain POC Entry Point

The tested RC2 toolkit remains the Power BI execution runtime. The experimental personal brain is isolated under `brain/` and is not part of the first-user release ZIP.

For brain work, an AI agent should read in this order:

1. `brain/AGENTS.md`
2. `brain/manifest.yaml`
3. `brain/README.md`
4. Only the reference, schema, prompt, or roadmap files relevant to the task

Recommended first local action:

```powershell
python .\brain\scripts\validate_foundation.py
```

Then copy `brain/templates/brain_config.example.yaml` into a separate local brain workspace, configure approved read-only source roots, and use `brain/prompts/WORK_MODEL_GOAL.md` for the first controlled harvest.

Do not put populated work sessions, credentials, Unity Catalog exports, PBIX metadata, or business results into this public generic repository.
