"""Console adapter for the offline simulator."""

import json
import sys

from .core import NOTICE, Simulator, marked


def _extract_global_flags(argv):
    cleaned = []
    globals_seen = {"output": "text", "profile": None, "target": None, "debug": False}
    index = 0
    value_flags = {"-o": "output", "--output": "output", "-p": "profile", "--profile": "profile", "-t": "target", "--target": "target"}
    while index < len(argv):
        token = argv[index]
        matched = False
        for flag, name in value_flags.items():
            if token == flag:
                if index + 1 >= len(argv):
                    raise ValueError("Flag %s requires a value." % flag)
                index += 1
                globals_seen[name] = argv[index]
                matched = True
                break
            if token.startswith(flag + "="):
                globals_seen[name] = token.split("=", 1)[1]
                matched = True
                break
        if not matched:
            if token == "--debug":
                globals_seen["debug"] = True
            else:
                cleaned.append(token)
        index += 1
    if globals_seen["output"] not in ("text", "json"):
        raise ValueError("--output must be text or json.")
    return cleaned, globals_seen


def _text_value(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (dict, list)):
        return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    if isinstance(value, str):
        # Keep Windows PowerShell 5.1 / legacy console output ASCII-safe and stable.
        return json.dumps(value, ensure_ascii=True)[1:-1]
    return str(value)


def render_text(payload):
    """Render a stable, tab-separated approximation of CLI text output."""
    visible = {key: value for key, value in payload.items() if not key.startswith("_simulat")}
    lines = ["[SIMULATED] No Databricks call was made."]
    if set(visible) == {"version", "latest"}:
        lines.append(str(visible["version"]))
        return "\n".join(lines) + "\n"
    list_keys = [key for key, value in visible.items() if isinstance(value, list)]
    if len(list_keys) == 1 and all(isinstance(item, dict) for item in visible[list_keys[0]]):
        items = visible[list_keys[0]]
        if not items:
            lines.append("(no results)")
        else:
            columns = sorted(set(key for item in items for key, value in item.items() if not isinstance(value, (dict, list))))
            lines.append("\t".join(columns))
            for item in items:
                lines.append("\t".join(_text_value(item.get(column)) for column in columns))
        return "\n".join(lines) + "\n"
    for key in sorted(visible):
        lines.append("%s\t%s" % (key, _text_value(visible[key])))
    return "\n".join(lines) + "\n"


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    global_flags = {"output": "text", "profile": None, "target": None, "debug": False}
    try:
        cleaned, global_flags = _extract_global_flags(argv)
        payload, exit_code = Simulator().execute(cleaned)
        if global_flags["profile"]:
            payload["_simulation_profile"] = global_flags["profile"]
        if global_flags["target"]:
            payload["_simulation_target_ignored"] = global_flags["target"]
    except ValueError as exc:
        payload = marked({"error_code": "INVALID_ARGUMENT", "message": str(exc)})
        exit_code = 2
    except Exception as exc:
        payload = marked({
            "error_code": "SIMULATOR_INTERNAL_ERROR",
            "message": "%s: %s" % (type(exc).__name__, exc),
        })
        exit_code = 1
    if global_flags.get("output") == "json":
        # JSON escapes preserve full Unicode while avoiding legacy Windows code-page crashes.
        sys.stdout.write(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=True) + "\n")
    else:
        sys.stdout.write(render_text(payload))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
