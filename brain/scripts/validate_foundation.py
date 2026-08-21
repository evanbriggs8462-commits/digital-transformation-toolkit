#!/usr/bin/env python3
"""Validate the generic brain foundation without touching live systems."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


def main() -> int:
    brain_root = Path(__file__).resolve().parents[1]
    results: dict[str, object] = {"brainRoot": str(brain_root), "checks": {}}
    checks: dict[str, object] = results["checks"]  # type: ignore[assignment]

    required = [
        "AGENTS.md",
        "README.md",
        "architecture.md",
        "manifest.yaml",
        "schemas/brain.schema.json",
        "sql/brain_registry.sql",
        "reference/SAP_REFERENCE.md",
        "reference/POWERBI_DATABRICKS_REFERENCE.md",
        "reference/OPENCODE_ARTIFACT_HARVEST.md",
        "prompts/WORK_MODEL_GOAL.md",
        "prompts/QUESTION_ROUTING.md",
        "prompts/GENIE_CONTEXT_COMPILER.md",
    ]
    missing = [path for path in required if not (brain_root / path).is_file()]
    checks["requiredFiles"] = {"status": "PASS" if not missing else "FAIL", "missing": missing}

    try:
        json.loads((brain_root / "schemas/brain.schema.json").read_text(encoding="utf-8"))
        checks["jsonSchemaSyntax"] = {"status": "PASS"}
    except Exception as exc:  # noqa: BLE001
        checks["jsonSchemaSyntax"] = {"status": "FAIL", "error": str(exc)}

    try:
        connection = sqlite3.connect(":memory:")
        connection.executescript((brain_root / "sql/brain_registry.sql").read_text(encoding="utf-8"))
        object_count = connection.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table','view','trigger')"
        ).fetchone()[0]
        checks["sqliteSchema"] = {"status": "PASS", "objectsCreated": object_count}
    except Exception as exc:  # noqa: BLE001
        checks["sqliteSchema"] = {"status": "FAIL", "error": str(exc)}

    try:
        import yaml  # type: ignore

        for relative in [
            "manifest.yaml",
            "examples/business_knowledge_cards.yaml",
            "examples/reconciliation_profiles.yaml",
            "templates/brain_config.example.yaml",
        ]:
            yaml.safe_load((brain_root / relative).read_text(encoding="utf-8"))
        checks["yamlSyntax"] = {"status": "PASS"}
    except ModuleNotFoundError:
        checks["yamlSyntax"] = {
            "status": "SKIP",
            "reason": "PyYAML is not installed; no installation is performed by this validator.",
        }
    except Exception as exc:  # noqa: BLE001
        checks["yamlSyntax"] = {"status": "FAIL", "error": str(exc)}

    failed = [name for name, value in checks.items() if isinstance(value, dict) and value.get("status") == "FAIL"]
    results["status"] = "FAIL" if failed else "PASS"
    results["failedChecks"] = failed
    print(json.dumps(results, indent=2))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
