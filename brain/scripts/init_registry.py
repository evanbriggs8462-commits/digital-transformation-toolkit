#!/usr/bin/env python3
"""Create an empty local brain registry from the checked-in SQLite schema."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".brain-poc/registry/brain.sqlite"),
        help="Destination SQLite file. Existing files are preserved unless --replace is supplied.",
    )
    parser.add_argument("--replace", action="store_true", help="Replace an existing registry file.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output.expanduser().resolve()
    schema = Path(__file__).resolve().parents[1] / "sql" / "brain_registry.sql"

    if output.exists() and not args.replace:
        raise SystemExit(f"Registry already exists: {output}. Use --replace to recreate it.")

    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    connection = sqlite3.connect(output)
    try:
        connection.executescript(schema.read_text(encoding="utf-8"))
        connection.commit()
    finally:
        connection.close()

    print(f"Created brain registry: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
