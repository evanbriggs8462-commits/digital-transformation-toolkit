#!/usr/bin/env python3
"""Fetch an ignored local text cache from an allowlisted official source index."""

from __future__ import annotations

import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from datetime import datetime, timezone
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


ALLOWED_HOSTS = {
    "docs.databricks.com",
    "github.com",
    "raw.githubusercontent.com",
}


def validate_url(url: str, label: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS or parsed.username or parsed.password:
        raise ValueError(f"{label} is not an allowlisted HTTPS URL: {url}")


class AllowlistedRedirectHandler(HTTPRedirectHandler):
    """Reject a redirect before urllib sends a request outside the allowlist."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        absolute_url = urljoin(req.full_url, newurl)
        validate_url(absolute_url, "Redirect target")
        return super().redirect_request(req, fp, code, msg, headers, absolute_url)


HTTPS_OPENER = build_opener(AllowlistedRedirectHandler())


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.suppressed = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        if tag in {"script", "style", "svg", "noscript"}:
            self.suppressed += 1
        elif not self.suppressed and tag in {"p", "div", "section", "article", "li", "tr", "h1", "h2", "h3", "h4", "pre", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "svg", "noscript"} and self.suppressed:
            self.suppressed -= 1
        elif not self.suppressed and tag in {"p", "div", "section", "article", "li", "tr", "h1", "h2", "h3", "h4", "pre"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.suppressed:
            self.parts.append(data)

    def text(self) -> str:
        value = html.unescape("".join(self.parts)).replace("\r\n", "\n").replace("\r", "\n")
        lines = [re.sub(r"[ \t]+", " ", line).strip() for line in value.splitlines()]
        compact: list[str] = []
        blank = False
        for line in lines:
            if line:
                compact.append(line)
                blank = False
            elif not blank and compact:
                compact.append("")
                blank = True
        return "\n".join(compact).strip() + "\n"


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", type=Path, default=root / "references" / "official_sources.json")
    parser.add_argument("--output", type=Path, default=root / ".cache" / "official-docs")
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--max-bytes", type=int, default=4_000_000)
    parser.add_argument("--check-only", action="store_true", help="Fetch and verify sources without keeping page text")
    parser.add_argument("--id", action="append", dest="ids", help="Fetch only the named source ID; repeatable")
    return parser.parse_args()


def validate_source(source: dict[str, object]) -> tuple[str, str]:
    source_id = str(source.get("id", ""))
    category = source.get("category")
    title = source.get("title")
    url = str(source.get("url", ""))
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", source_id):
        raise ValueError(f"Invalid source id: {source_id!r}")
    if not isinstance(category, str) or not category.strip():
        raise ValueError(f"Source {source_id!r} needs a non-empty category")
    if not isinstance(title, str) or not title.strip():
        raise ValueError(f"Source {source_id!r} needs a non-empty title")
    validate_url(url, f"Source {source_id!r}")
    return source_id, url


def validate_index(index: object) -> list[dict[str, object]]:
    if not isinstance(index, dict):
        raise ValueError("Source index must be a JSON object")
    if index.get("schema_version") != 1:
        raise ValueError("Unsupported source-index schema_version; expected 1")
    raw_sources = index.get("sources")
    if not isinstance(raw_sources, list):
        raise ValueError("Source index 'sources' must be an array")
    sources: list[dict[str, object]] = []
    seen_ids: set[str] = set()
    seen_urls: set[str] = set()
    for position, raw_source in enumerate(raw_sources):
        if not isinstance(raw_source, dict):
            raise ValueError(f"Source at array index {position} must be an object")
        source = dict(raw_source)
        source_id, url = validate_source(source)
        if source_id in seen_ids:
            raise ValueError(f"Duplicate source id: {source_id}")
        if url in seen_urls:
            raise ValueError(f"Duplicate source URL: {url}")
        seen_ids.add(source_id)
        seen_urls.add(url)
        sources.append(source)
    return sources


def fetch(url: str, timeout: int, max_bytes: int) -> tuple[bytes, str, str, int]:
    request = Request(url, headers={"User-Agent": "DatabricksAgentToolkit/0.1 docs-cache"})
    with HTTPS_OPENER.open(request, timeout=timeout) as response:
        final_url = response.geturl()
        validate_url(final_url, "Final response URL")
        payload = response.read(max_bytes + 1)
        if len(payload) > max_bytes:
            raise ValueError(f"Response exceeded --max-bytes ({max_bytes})")
        return payload, response.headers.get_content_type(), final_url, int(response.status)


def main() -> int:
    args = parse_args()
    index = json.loads(args.index.read_text(encoding="utf-8"))
    sources = validate_index(index)
    if args.ids:
        wanted = set(args.ids)
        sources = [source for source in sources if str(source.get("id")) in wanted]
        missing = wanted - {str(source.get("id")) for source in sources}
        if missing:
            raise SystemExit(f"Unknown source IDs: {', '.join(sorted(missing))}")
    args.output.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, object]] = []
    failures = 0
    for source in sources:
        source_id, url = validate_source(source)
        record: dict[str, object] = {
            "id": source_id,
            "url": url,
            "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
            "status": "failed",
        }
        try:
            payload, content_type, final_url, status_code = fetch(url, args.timeout, args.max_bytes)
            digest = hashlib.sha256(payload).hexdigest().upper()
            record.update({
                "status": "ok",
                "http_status": status_code,
                "final_url": final_url,
                "content_type": content_type,
                "bytes": len(payload),
                "sha256": digest,
            })
            if not args.check_only:
                if content_type in {"text/html", "application/xhtml+xml"}:
                    parser = TextExtractor()
                    parser.feed(payload.decode("utf-8", errors="replace"))
                    text = parser.text()
                else:
                    text = payload.decode("utf-8", errors="replace")
                (args.output / f"{source_id}.txt").write_text(text, encoding="utf-8")
            print(f"OK   {source_id} {status_code} {len(payload)} bytes")
        except (HTTPError, URLError, TimeoutError, ValueError, OSError) as error:
            failures += 1
            record["error_type"] = type(error).__name__
            record["error"] = str(error)
            print(f"FAIL {source_id} {type(error).__name__}: {error}", file=sys.stderr)
        results.append(record)
    manifest = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_index": str(args.index.resolve()),
        "check_only": bool(args.check_only),
        "results": results,
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Sources: {len(results) - failures} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
