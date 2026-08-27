"""Offline Databricks CLI simulation state and command dispatcher."""

import copy
import json
import math
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .sql_engine import SQLExecutionError, evaluate, normalize_parameters, truncate_rows, validate_read_only


NOTICE = "SIMULATED OUTPUT - no Databricks credentials, config, or network connection were used."


class CommandError(Exception):
    def __init__(self, code, message, exit_code=1, http_status=None):
        Exception.__init__(self, message)
        self.code = code
        self.message = message
        self.exit_code = exit_code
        self.http_status = http_status


def marked(payload, http_status=None):
    if payload is None:
        payload = {}
    result = copy.deepcopy(payload)
    if not isinstance(result, dict):
        result = {"items": result}
    result["_simulated"] = True
    result["_simulation_notice"] = NOTICE
    if http_status is not None:
        result["_http"] = {"status_code": int(http_status)}
    return result


def error_payload(error):
    payload = {"error_code": error.code, "message": error.message}
    return marked(payload, error.http_status)


class StateStore(object):
    def __init__(self, project_root=None, state_dir=None):
        self.project_root = Path(project_root or Path(__file__).resolve().parents[1]).resolve()
        self.seed_path = self.project_root / "fixtures" / "seed.json"
        self.state_dir = Path(state_dir).resolve() if state_dir else self.project_root / ".sim-state"
        self.state_path = self.state_dir / "state.json"

    def _seed(self):
        with self.seed_path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def load(self):
        if not self.state_path.exists():
            state = self._seed()
            self.save(state)
            return state
        with self.state_path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def save(self, state):
        self.state_dir.mkdir(parents=True, exist_ok=True)
        temporary = self.state_dir / "state.json.tmp"
        with temporary.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(state, handle, indent=2, sort_keys=True, ensure_ascii=False)
            handle.write("\n")
        os.replace(str(temporary), str(self.state_path))

    def reset(self):
        # Reset only the state file. Never recursively remove an injected path.
        state = self._seed()
        self.save(state)
        return state


def _pop_options(args, value_flags=None, bool_flags=None):
    value_flags = set(value_flags or [])
    bool_flags = set(bool_flags or [])
    options = {}
    positionals = []
    index = 0
    while index < len(args):
        token = args[index]
        if token.startswith("--") and "=" in token:
            flag, value = token.split("=", 1)
            if flag not in value_flags:
                raise CommandError("UNKNOWN_FLAG", "Unknown flag: %s" % flag, 2)
            options[flag] = value
        elif token in bool_flags:
            options[token] = True
        elif token in value_flags:
            if index + 1 >= len(args):
                raise CommandError("MISSING_FLAG_VALUE", "Flag %s requires a value." % token, 2)
            index += 1
            options[token] = args[index]
        elif token.startswith("-"):
            raise CommandError("UNKNOWN_FLAG", "Unknown flag: %s" % token, 2)
        else:
            positionals.append(token)
        index += 1
    return positionals, options


def _expect(positionals, count, usage):
    if len(positionals) != count:
        raise CommandError("INVALID_ARGUMENT", "Usage: %s" % usage, 2)


def _integer(value, name, minimum=0):
    try:
        parsed = int(value)
    except (ValueError, TypeError):
        raise CommandError("INVALID_ARGUMENT", "%s must be an integer." % name, 2)
    if parsed < minimum:
        raise CommandError("INVALID_ARGUMENT", "%s must be at least %s." % (name, minimum), 2)
    return parsed


def _limit(items, options, names=("--limit", "--page-size", "--max-results")):
    limit = None
    for name in names:
        if name in options:
            candidate = _integer(options[name], name, 0)
            limit = candidate if limit is None else min(limit, candidate)
    return items if limit in (None, 0) else items[:limit]


def load_json_argument(value):
    if value is None:
        return {}
    text = value
    if value.startswith("@"):
        path_text = value[1:]
        if not path_text or path_text == "-":
            raise CommandError("INVALID_JSON", "--json @- is disabled; use an inline object or @file.json.", 2)
        path = Path(path_text).resolve()
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise CommandError("INVALID_JSON", "Unable to read JSON file: %s" % exc, 2)
    try:
        body = json.loads(text)
    except (ValueError, TypeError) as exc:
        raise CommandError("INVALID_JSON", "Invalid JSON: %s" % exc, 2)
    if not isinstance(body, dict):
        raise CommandError("INVALID_JSON", "--json must contain a JSON object.", 2)
    return body


class Simulator(object):
    def __init__(self, store=None):
        self.store = store or StateStore()

    def execute(self, args):
        if not args:
            return marked({"usage": self.help_text()}), 0
        try:
            payload = self._dispatch(list(args))
            return marked(payload), 0
        except CommandError as exc:
            return error_payload(exc), exc.exit_code

    def help_text(self):
        return (
            "databricks-sim.ps1 [global flags] COMMAND ...\n"
            "Offline families: current-user, auth, warehouses, clusters, jobs, queries, "
            "query-history, catalogs, schemas, tables, volumes, workspace, fs, api.\n"
            "Reset: databricks-sim.ps1 sim reset"
        )

    def _dispatch(self, args):
        command = args.pop(0)
        if command in ("help", "--help", "-h"):
            return {"usage": self.help_text()}
        if command in ("version", "--version", "-v"):
            positionals, options = _pop_options(args, bool_flags={"--check"})
            _expect(positionals, 0, "databricks version [flags]")
            return {"version": "Databricks CLI simulator 1.14.0-sim.1", "latest": True if options.get("--check") else None}
        if command == "quickstart":
            _expect(_pop_options(args)[0], 0, "databricks quickstart")
            return {
                "guide": [
                    "This is an offline simulator, not a Databricks workspace.",
                    "Try: warehouses list; catalogs list; api post /api/2.0/sql/statements --json '@examples/statement-inline.json'",
                    "Poll statements with api get /api/2.0/sql/statements/<statement_id>.",
                    "Reset all local changes with: sim reset",
                ]
            }
        if command == "sim":
            return self._sim(args)
        if command == "current-user":
            return self._current_user(args)
        if command == "auth":
            return self._auth(args)
        if command == "api":
            return self._api(args)
        handlers = {
            "warehouses": self._warehouses,
            "clusters": self._clusters,
            "jobs": self._jobs,
            "queries": self._queries,
            "query-history": self._query_history,
            "catalogs": self._catalogs,
            "schemas": self._schemas,
            "tables": self._tables,
            "volumes": self._volumes,
            "workspace": self._workspace,
            "fs": self._fs,
        }
        if command not in handlers:
            raise CommandError("UNKNOWN_COMMAND", "Unknown command: %s" % command, 2)
        return handlers[command](args)

    def _sim(self, args):
        if args == ["reset"]:
            self.store.reset()
            return {"reset": True, "state_path": str(self.store.state_path), "message": "Simulator state restored from fixtures/seed.json."}
        raise CommandError("INVALID_ARGUMENT", "Usage: databricks sim reset", 2)

    def _current_user(self, args):
        if not args or args.pop(0) != "me":
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks current-user me [flags]", 2)
        positionals, options = _pop_options(args, {"--attributes", "--excluded-attributes"})
        _expect(positionals, 0, "databricks current-user me [flags]")
        user = copy.deepcopy(self.store.load()["current_user"])
        if "--attributes" in options:
            wanted = set(part.strip() for part in options["--attributes"].split(","))
            user = {key: value for key, value in user.items() if key in wanted or key == "schemas"}
        if "--excluded-attributes" in options:
            excluded = set(part.strip() for part in options["--excluded-attributes"].split(","))
            user = {key: value for key, value in user.items() if key not in excluded}
        return user

    def _auth(self, args):
        if not args or args.pop(0) != "profiles":
            raise CommandError("OFFLINE_AUTH_DISABLED", "Only 'auth profiles' is simulated; login and token access are disabled.", 2)
        positionals, options = _pop_options(
            args,
            {"--account-id", "--host", "--workspace-id"},
            {"--skip-validate"},
        )
        _expect(positionals, 0, "databricks auth profiles [flags]")
        return {
            "profiles": self.store.load()["auth_profiles"],
            "filters_ignored_offline": sorted(key for key in options if key != "--skip-validate"),
        }

    def _warehouses(self, args):
        if not args:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks warehouses COMMAND", 2)
        action = args.pop(0)
        state = self.store.load()
        if action == "list":
            pos, opts = _pop_options(args, {"--limit", "--page-size", "--run-as-user-id"})
            _expect(pos, 0, "databricks warehouses list [flags]")
            values = sorted(state["warehouses"].values(), key=lambda item: item["name"])
            return {"warehouses": _limit(values, opts)}
        if action == "get":
            pos, opts = _pop_options(args)
        elif action in ("start", "stop"):
            pos, opts = _pop_options(args, {"--timeout"}, {"--no-wait"})
        else:
            raise CommandError("UNKNOWN_COMMAND", "Unsupported warehouses command: %s" % action, 2)
        _expect(pos, 1, "databricks warehouses %s ID [flags]" % action)
        warehouse = state["warehouses"].get(pos[0])
        if not warehouse:
            raise CommandError("RESOURCE_DOES_NOT_EXIST", "Warehouse not found: %s" % pos[0])
        if action == "get":
            return warehouse
        if action in ("start", "stop"):
            warehouse["state"] = "STARTING" if action == "start" and opts.get("--no-wait") else "RUNNING" if action == "start" else "STOPPING" if opts.get("--no-wait") else "STOPPED"
            self.store.save(state)
            return warehouse
        raise CommandError("UNKNOWN_COMMAND", "Unsupported warehouses command: %s" % action, 2)

    def _clusters(self, args):
        if not args:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks clusters COMMAND", 2)
        action = args.pop(0)
        state = self.store.load()
        if action == "list":
            pos, opts = _pop_options(args, {"--cluster-sources", "--cluster-states", "--limit", "--page-size", "--policy-id"}, {"--is-pinned"})
            _expect(pos, 0, "databricks clusters list [flags]")
            values = sorted(state["clusters"].values(), key=lambda item: item["cluster_name"])
            if "--cluster-states" in opts:
                wanted = set(part.upper() for part in opts["--cluster-states"].split(","))
                values = [item for item in values if item["state"] in wanted]
            return {"clusters": _limit(values, opts)}
        if action == "get":
            pos, opts = _pop_options(args)
        elif action in ("start", "delete"):
            pos, opts = _pop_options(args, {"--json", "--timeout"}, {"--no-wait"})
        else:
            raise CommandError("UNKNOWN_COMMAND", "Unsupported clusters command: %s" % action, 2)
        _expect(pos, 1, "databricks clusters %s CLUSTER_ID [flags]" % action)
        cluster = state["clusters"].get(pos[0])
        if not cluster:
            raise CommandError("RESOURCE_DOES_NOT_EXIST", "Cluster not found: %s" % pos[0])
        if action == "get":
            return cluster
        if action == "start":
            cluster["state"] = "PENDING" if opts.get("--no-wait") else "RUNNING"
            cluster["state_message"] = "Simulated start requested."
        elif action == "delete":
            cluster["state"] = "TERMINATING" if opts.get("--no-wait") else "TERMINATED"
            cluster["state_message"] = "Simulated termination requested."
        else:
            raise CommandError("UNKNOWN_COMMAND", "Unsupported clusters command: %s" % action, 2)
        self.store.save(state)
        return cluster

    def _jobs(self, args):
        if not args:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks jobs COMMAND", 2)
        action = args.pop(0)
        state = self.store.load()
        if action == "list":
            pos, opts = _pop_options(args, {"--limit", "--name", "--offset"}, {"--expand-tasks"})
            _expect(pos, 0, "databricks jobs list [flags]")
            jobs = sorted(state["jobs"].values(), key=lambda item: item["job_id"])
            if "--name" in opts:
                jobs = [job for job in jobs if job["settings"]["name"].lower() == opts["--name"].lower()]
            offset = _integer(opts.get("--offset", 0), "--offset", 0)
            return {"jobs": _limit(jobs[offset:], opts), "has_more": False}
        if action == "get":
            pos, opts = _pop_options(args, {"--page-token"}, {"--include-trigger-state"})
            _expect(pos, 1, "databricks jobs get JOB_ID [flags]")
            job = state["jobs"].get(pos[0])
            if not job:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Job not found: %s" % pos[0])
            return job
        if action == "run-now":
            pos, opts = _pop_options(args, {"--idempotency-token", "--json", "--performance-target", "--timeout"}, {"--no-wait"})
            _expect(pos, 1, "databricks jobs run-now JOB_ID [flags]")
            job = state["jobs"].get(pos[0])
            if not job:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Job not found: %s" % pos[0])
            body = load_json_argument(opts.get("--json"))
            token = opts.get("--idempotency-token") or body.get("idempotency_token")
            if token is not None and len(str(token)) > 64:
                raise CommandError("INVALID_PARAMETER_VALUE", "idempotency_token cannot exceed 64 characters.")
            token_map = state.setdefault("idempotency_tokens", {})
            token_key = str(token) if token else None
            if token_key and token_key in token_map:
                existing = state["runs"][str(token_map[token_key])]
                return {"run_id": existing["run_id"], "number_in_job": 1, "state": existing["state"], "idempotent_replay": True}
            state["counters"]["job_run"] += 1
            run_id = state["counters"]["job_run"]
            pending = bool(opts.get("--no-wait"))
            run = {
                "run_id": run_id,
                "job_id": job["job_id"],
                "run_name": job["settings"]["name"],
                "start_time": state["clock_ms"] + run_id,
                "parameters": body,
                "poll_count": 0,
                "state": {
                    "life_cycle_state": "PENDING" if pending else "TERMINATED",
                    "result_state": None if pending else "SUCCESS",
                    "state_message": "Simulated run queued." if pending else "Simulated run completed without executing code.",
                },
            }
            state["runs"][str(run_id)] = run
            if token_key:
                token_map[token_key] = run_id
            self.store.save(state)
            return {"run_id": run_id, "number_in_job": 1, "state": run["state"]}
        if action == "get-run":
            pos, opts = _pop_options(args, {"--page-token"}, {"--include-history", "--include-resolved-values"})
            _expect(pos, 1, "databricks jobs get-run RUN_ID [flags]")
            run = state["runs"].get(pos[0])
            if not run:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Run not found: %s" % pos[0])
            lifecycle = run["state"]["life_cycle_state"]
            if lifecycle == "PENDING":
                run["state"].update({"life_cycle_state": "RUNNING", "state_message": "Simulated run is running."})
            elif lifecycle == "RUNNING":
                run["state"].update({"life_cycle_state": "TERMINATED", "result_state": "SUCCESS", "state_message": "Simulated run completed without executing code."})
            elif lifecycle == "TERMINATING":
                run["state"].update({"life_cycle_state": "TERMINATED", "result_state": "CANCELED", "state_message": "Simulated run canceled."})
            run["poll_count"] += 1
            self.store.save(state)
            return run
        if action == "cancel-run":
            pos, opts = _pop_options(args, {"--json", "--timeout"}, {"--no-wait"})
            _expect(pos, 1, "databricks jobs cancel-run RUN_ID [flags]")
            run = state["runs"].get(pos[0])
            if not run:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Run not found: %s" % pos[0])
            if run["state"]["life_cycle_state"] != "TERMINATED":
                run["state"].update({"life_cycle_state": "TERMINATING" if opts.get("--no-wait") else "TERMINATED", "result_state": None if opts.get("--no-wait") else "CANCELED", "state_message": "Simulated cancellation requested."})
                self.store.save(state)
            return {"run_id": run["run_id"], "state": run["state"]}
        raise CommandError("UNKNOWN_COMMAND", "Unsupported jobs command: %s" % action, 2)

    def _queries(self, args):
        if not args:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks queries COMMAND", 2)
        action = args.pop(0)
        state = self.store.load()
        if action == "list":
            pos, opts = _pop_options(args, {"--limit", "--page-size"})
            _expect(pos, 0, "databricks queries list [flags]")
            values = sorted(state["queries"].values(), key=lambda item: item["display_name"])
            return {"results": _limit(values, opts), "next_page_token": None}
        if action in ("get", "delete"):
            pos, opts = _pop_options(args)
            _expect(pos, 1, "databricks queries %s ID" % action)
            query = state["queries"].get(pos[0])
            if not query:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Query not found: %s" % pos[0])
            if action == "get":
                return query
            del state["queries"][pos[0]]
            self.store.save(state)
            return {"deleted": True, "id": pos[0]}
        if action == "create":
            pos, opts = _pop_options(args, {"--json"}, {"--auto-resolve-display-name"})
            _expect(pos, 0, "databricks queries create --json JSON")
            body = load_json_argument(opts.get("--json"))
            for required in ("display_name", "query_text", "warehouse_id"):
                if not body.get(required):
                    raise CommandError("INVALID_PARAMETER_VALUE", "Missing query field: %s" % required)
            try:
                validate_read_only(body["query_text"])
            except SQLExecutionError as exc:
                raise CommandError(exc.code, exc.message)
            state["counters"]["query"] += 1
            query_id = "query-sim-%03d" % state["counters"]["query"]
            query = copy.deepcopy(body)
            query.update({"id": query_id, "owner_user_name": "agent@simulated.invalid", "created_at": state["clock_ms"], "updated_at": state["clock_ms"]})
            state["queries"][query_id] = query
            self.store.save(state)
            return query
        if action == "update":
            pos, opts = _pop_options(args, {"--json"}, {"--auto-resolve-display-name"})
            _expect(pos, 2, "databricks queries update ID UPDATE_MASK --json JSON")
            query = state["queries"].get(pos[0])
            if not query:
                raise CommandError("RESOURCE_DOES_NOT_EXIST", "Query not found: %s" % pos[0])
            body = load_json_argument(opts.get("--json"))
            fields = list(body) if pos[1] == "*" else [field.strip() for field in pos[1].split(",")]
            for field in fields:
                if field not in body:
                    raise CommandError("INVALID_PARAMETER_VALUE", "Update mask field missing from JSON: %s" % field)
                if field == "query_text":
                    try:
                        validate_read_only(body[field])
                    except SQLExecutionError as exc:
                        raise CommandError(exc.code, exc.message)
                query[field] = body[field]
            query["updated_at"] = state["clock_ms"] + state["counters"]["query"]
            self.store.save(state)
            return query
        raise CommandError("UNKNOWN_COMMAND", "Unsupported queries command: %s" % action, 2)

    def _query_history(self, args):
        if not args or args.pop(0) != "list":
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks query-history list [flags]", 2)
        pos, opts = _pop_options(args, {"--max-results", "--page-token"}, {"--include-metrics"})
        _expect(pos, 0, "databricks query-history list [flags]")
        history = list(reversed(self.store.load()["query_history"]))
        if not opts.get("--include-metrics"):
            history = [{key: value for key, value in item.items() if key != "metrics"} for item in history]
        return {"res": _limit(history, opts), "has_next_page": False, "next_page_token": None}

    def _resource_family(self, family, args, list_positionals, get_action, list_value_flags, list_bool_flags, get_bool_flags):
        if not args:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks %s COMMAND" % family, 2)
        action = args.pop(0)
        state = self.store.load()
        data = state[family]
        if action == "list":
            pos, opts = _pop_options(args, list_value_flags, list_bool_flags)
            _expect(pos, list_positionals, "databricks %s list %s [flags]" % (family, " ".join(["NAME"] * list_positionals)))
            values = list(data.values())
            if family == "schemas":
                values = [item for item in values if item["catalog_name"] == pos[0]]
            elif family in ("tables", "volumes"):
                values = [item for item in values if item["catalog_name"] == pos[0] and item["schema_name"] == pos[1]]
            values.sort(key=lambda item: item.get("full_name", item.get("name", "")))
            if family == "tables" and opts.get("--omit-columns"):
                values = [{key: value for key, value in item.items() if key != "columns"} for item in values]
            return {family: _limit(values, opts)}
        if action != get_action:
            raise CommandError("UNKNOWN_COMMAND", "Unsupported %s command: %s" % (family, action), 2)
        pos, opts = _pop_options(args, bool_flags=get_bool_flags)
        _expect(pos, 1, "databricks %s %s NAME [flags]" % (family, action))
        item = data.get(pos[0])
        if not item:
            raise CommandError("RESOURCE_DOES_NOT_EXIST", "%s not found: %s" % (family[:-1].title(), pos[0]))
        return item

    def _catalogs(self, args):
        return self._resource_family(
            "catalogs", args, 0, "get", {"--limit"},
            {"--include-browse", "--include-unbound"}, {"--include-browse"},
        )

    def _schemas(self, args):
        return self._resource_family(
            "schemas", args, 1, "get", {"--limit"}, {"--include-browse"}, {"--include-browse"},
        )

    def _tables(self, args):
        return self._resource_family(
            "tables", args, 2, "get", {"--limit"},
            {"--include-browse", "--include-manifest-capabilities", "--omit-columns", "--omit-properties", "--omit-username"},
            {"--include-browse", "--include-delta-metadata", "--include-manifest-capabilities"},
        )

    def _volumes(self, args):
        return self._resource_family(
            "volumes", args, 2, "read", {"--limit", "--max-results"}, {"--include-browse"}, {"--include-browse"},
        )

    def _workspace(self, args):
        if not args or args.pop(0) != "list":
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks workspace list PATH [flags]", 2)
        pos, opts = _pop_options(args, {"--limit", "--notebooks-modified-after"})
        _expect(pos, 1, "databricks workspace list PATH [flags]")
        path = pos[0].rstrip("/") or "/"
        if not path.startswith("/"):
            raise CommandError("INVALID_PARAMETER_VALUE", "Workspace path must be absolute.")
        objects = self.store.load()["workspace_objects"]
        prefix = "/" if path == "/" else path + "/"
        children = []
        exact = next((item for item in objects if item["path"] == path), None)
        if exact and exact["object_type"] != "DIRECTORY":
            children = [exact]
        else:
            for item in objects:
                remainder = item["path"][len(prefix):] if item["path"].startswith(prefix) else ""
                if remainder and "/" not in remainder:
                    children.append(item)
        if not children and not (path == "/" or (exact and exact["object_type"] == "DIRECTORY")):
            raise CommandError("RESOURCE_DOES_NOT_EXIST", "Workspace path not found: %s" % path)
        return {"objects": _limit(children, opts)}

    def _fs(self, args):
        if not args or args.pop(0) != "ls":
            raise CommandError("READ_ONLY_VIOLATION", "Only 'fs ls' is available in the read-only simulator.", 2)
        pos, opts = _pop_options(args, bool_flags={"--absolute", "--long", "-l"})
        _expect(pos, 1, "databricks fs ls DIR_PATH [flags]")
        path = pos[0].rstrip("/")
        if not path.startswith("dbfs:/"):
            raise CommandError("INVALID_PARAMETER_VALUE", "Remote paths must use the dbfs:/ scheme.")
        entries = self.store.load()["fs_entries"]
        prefix = path + "/"
        exact = [item for item in entries if item["path"] == path]
        if exact and not exact[0]["is_dir"]:
            selected = exact
        else:
            selected = [item for item in entries if item["path"].startswith(prefix) and "/" not in item["path"][len(prefix):]]
        if not selected:
            raise CommandError("RESOURCE_DOES_NOT_EXIST", "Filesystem path not found: %s" % path)
        if not opts.get("--absolute"):
            selected = [dict(item, display_name=item["name"]) for item in selected]
        return {"files": selected}

    def _api(self, args):
        if len(args) < 2:
            raise CommandError("INVALID_ARGUMENT", "Usage: databricks api get|post PATH [flags]", 2)
        method = args.pop(0).lower()
        if method not in ("get", "post"):
            raise CommandError("READ_ONLY_VIOLATION", "Only api get and post are simulated.", 2)
        pos, opts = _pop_options(args, {"--json", "--workspace-id"}, {"--account"})
        _expect(pos, 1, "databricks api %s PATH [flags]" % method)
        path = pos[0]
        if opts.get("--account") and opts.get("--workspace-id"):
            raise CommandError("INVALID_ARGUMENT", "--account and --workspace-id are mutually exclusive.", 2)
        body = load_json_argument(opts.get("--json"))
        payload, http_status = self._statement_api(method, path, body)
        return marked(payload, http_status)

    def _statement_api(self, method, path, body):
        normalized = "/" + path.lstrip("/").split("?", 1)[0].rstrip("/")
        collection = "/api/2.0/sql/statements"
        if method == "post" and normalized == collection:
            return self._create_statement(body), 200
        cancel = re.match(r"^/api/2\.0/sql/statements/([^/]+)/cancel$", normalized)
        chunk = re.match(r"^/api/2\.0/sql/statements/([^/]+)/result/chunks/([0-9]+)$", normalized)
        single = re.match(r"^/api/2\.0/sql/statements/([^/]+)$", normalized)
        if method == "post" and cancel:
            return self._cancel_statement(cancel.group(1)), 200
        if method == "get" and chunk:
            return self._get_chunk(chunk.group(1), int(chunk.group(2))), 200
        if method == "get" and single:
            return self._get_statement(single.group(1)), 200
        raise CommandError("ENDPOINT_NOT_FOUND", "No simulated endpoint for %s %s" % (method.upper(), normalized), 1, 404)

    def _create_statement(self, body):
        if not isinstance(body, dict):
            raise CommandError("INVALID_PARAMETER_VALUE", "Request body must be an object.", 1, 400)
        sql = body.get("statement")
        warehouse_id = body.get("warehouse_id")
        if not warehouse_id:
            raise CommandError("INVALID_PARAMETER_VALUE", "warehouse_id is required.", 1, 400)
        state = self.store.load()
        warehouse = state["warehouses"].get(str(warehouse_id))
        if not warehouse:
            raise CommandError("WAREHOUSE_NOT_FOUND", "Warehouse not found: %s" % warehouse_id, 1, 404)
        if warehouse["state"] != "RUNNING":
            raise CommandError("WAREHOUSE_NOT_RUNNING", "Warehouse %s is not RUNNING." % warehouse_id, 1, 409)
        disposition = str(body.get("disposition", "INLINE")).upper()
        result_format = str(body.get("format", "JSON_ARRAY")).upper()
        if disposition not in ("INLINE", "EXTERNAL_LINKS"):
            raise CommandError("INVALID_PARAMETER_VALUE", "disposition must be INLINE or EXTERNAL_LINKS.", 1, 400)
        if result_format != "JSON_ARRAY":
            raise CommandError("SIMULATOR_FORMAT_UNSUPPORTED", "Only JSON_ARRAY is simulated.", 1, 400)
        wait_timeout = str(body.get("wait_timeout", "10s"))
        timeout_match = re.match(r"^([0-9]+)s$", wait_timeout)
        if not timeout_match or (int(timeout_match.group(1)) not in (0,) and not 5 <= int(timeout_match.group(1)) <= 50):
            raise CommandError("INVALID_PARAMETER_VALUE", "wait_timeout must be 0s or between 5s and 50s.", 1, 400)
        on_wait_timeout = str(body.get("on_wait_timeout", "CONTINUE")).upper()
        if on_wait_timeout not in ("CONTINUE", "CANCEL"):
            raise CommandError("INVALID_PARAMETER_VALUE", "on_wait_timeout must be CONTINUE or CANCEL.", 1, 400)
        try:
            validate_read_only(sql)
            parameters, parameter_types = normalize_parameters(body.get("parameters"), sql)
        except SQLExecutionError as exc:
            raise CommandError(exc.code, exc.message, 1, 400)
        row_limit = body.get("row_limit")
        byte_limit = body.get("byte_limit")
        if row_limit is not None:
            row_limit = self._body_integer(row_limit, "row_limit")
        if byte_limit is not None:
            byte_limit = self._body_integer(byte_limit, "byte_limit")
        terminal_error = None
        columns = []
        rows = []
        try:
            columns, rows = evaluate(sql, state, parameters, parameter_types)
        except SQLExecutionError as exc:
            terminal_error = {"error_code": exc.code, "message": exc.message}
        rows, truncated = truncate_rows(rows, row_limit, byte_limit)
        state["counters"]["statement"] += 1
        statement_id = "stmt-sim-%06d" % state["counters"]["statement"]
        statement = {
            "statement_id": statement_id,
            "warehouse_id": warehouse_id,
            "statement": sql,
            "catalog": body.get("catalog", "main"),
            "schema": body.get("schema", "analytics"),
            "disposition": disposition,
            "format": result_format,
            "status": {"state": "PENDING"},
            "poll_count": 0,
            "cancel_requested": False,
            "wait_timeout": wait_timeout,
            "on_wait_timeout": on_wait_timeout,
            "terminal_error": terminal_error,
            "columns": columns,
            "rows": rows,
            "truncated": truncated,
            "chunk_size": 2,
            "external_expiration": (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat().replace("+00:00", "Z"),
        }
        state["statements"][statement_id] = statement
        slow = bool(re.search(r"SIMULATE\s*:\s*SLOW", sql, re.IGNORECASE))
        if wait_timeout != "0s" and not slow:
            statement["status"] = {"state": "FAILED", "error": terminal_error} if terminal_error else {"state": "SUCCEEDED"}
        elif slow and wait_timeout != "0s" and on_wait_timeout == "CANCEL":
            statement["status"] = {"state": "CANCELED"}
        state["query_history"].append({
            "query_id": statement_id,
            "statement_id": statement_id,
            "query_text": sql,
            "warehouse_id": warehouse_id,
            "status": statement["status"]["state"],
            "user_name": "agent@simulated.invalid",
            "start_time_ms": state["clock_ms"] + state["counters"]["statement"],
            "metrics": {"rows_produced_count": len(rows) if statement["status"]["state"] == "SUCCEEDED" else 0, "total_time_ms": 1 if statement["status"]["state"] in ("SUCCEEDED", "FAILED") else 0},
        })
        self.store.save(state)
        return self._statement_payload(statement)

    def _body_integer(self, value, name):
        try:
            parsed = int(value)
        except (ValueError, TypeError):
            raise CommandError("INVALID_PARAMETER_VALUE", "%s must be an integer." % name, 1, 400)
        if parsed < 0:
            raise CommandError("INVALID_PARAMETER_VALUE", "%s cannot be negative." % name, 1, 400)
        return parsed

    def _get_statement(self, statement_id):
        state = self.store.load()
        statement = state["statements"].get(statement_id)
        if not statement:
            raise CommandError("STATEMENT_NOT_FOUND", "Statement not found: %s" % statement_id, 1, 404)
        current = statement["status"]["state"]
        if statement["cancel_requested"] and current in ("PENDING", "RUNNING"):
            statement["status"] = {"state": "CANCELED"}
        elif current == "PENDING":
            statement["status"] = {"state": "RUNNING"}
        elif current == "RUNNING":
            if statement["terminal_error"]:
                statement["status"] = {"state": "FAILED", "error": statement["terminal_error"]}
            else:
                statement["status"] = {"state": "SUCCEEDED"}
        statement["poll_count"] += 1
        history = next((item for item in state["query_history"] if item["statement_id"] == statement_id), None)
        if history:
            history["status"] = statement["status"]["state"]
            history["metrics"] = {"rows_produced_count": len(statement["rows"]), "total_time_ms": statement["poll_count"] * 25}
        self.store.save(state)
        return self._statement_payload(statement)

    def _cancel_statement(self, statement_id):
        state = self.store.load()
        statement = state["statements"].get(statement_id)
        if not statement:
            raise CommandError("STATEMENT_NOT_FOUND", "Statement not found: %s" % statement_id, 1, 404)
        if statement["status"]["state"] in ("PENDING", "RUNNING"):
            statement["cancel_requested"] = True
            self.store.save(state)
        return {}

    def _get_chunk(self, statement_id, chunk_index):
        state = self.store.load()
        statement = state["statements"].get(statement_id)
        if not statement:
            raise CommandError("STATEMENT_NOT_FOUND", "Statement not found: %s" % statement_id, 1, 404)
        if statement["status"]["state"] != "SUCCEEDED":
            raise CommandError("STATEMENT_NOT_FINISHED", "Result chunks are available only after SUCCEEDED.", 1, 409)
        total_chunks = self._chunk_count(statement)
        if chunk_index < 0 or chunk_index >= total_chunks:
            raise CommandError("CHUNK_NOT_FOUND", "Chunk index not found: %s" % chunk_index, 1, 404)
        return self._result_chunk(statement, chunk_index)

    def _statement_payload(self, statement):
        payload = {"statement_id": statement["statement_id"], "status": statement["status"]}
        if statement["status"]["state"] == "SUCCEEDED":
            payload["manifest"] = self._manifest(statement)
            if self._chunk_count(statement):
                payload["result"] = self._result_chunk(statement, 0)
            elif statement["disposition"] == "EXTERNAL_LINKS":
                payload["result"] = {"chunk_index": 0, "row_offset": 0, "row_count": 0, "external_links": []}
            else:
                payload["result"] = {"chunk_index": 0, "row_offset": 0, "row_count": 0, "data_array": []}
        return payload

    def _chunk_count(self, statement):
        return int(math.ceil(float(len(statement["rows"])) / float(statement["chunk_size"]))) if statement["rows"] else 0

    def _wire_rows(self, rows):
        result = []
        for row in rows:
            wire = []
            for value in row:
                if value is None:
                    wire.append(None)
                elif isinstance(value, bool):
                    wire.append("true" if value else "false")
                else:
                    wire.append(str(value))
            result.append(wire)
        return result

    def _manifest(self, statement):
        wire_rows = self._wire_rows(statement["rows"])
        byte_count = len(json.dumps(wire_rows, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
        chunks = []
        for chunk_index in range(self._chunk_count(statement)):
            start = chunk_index * statement["chunk_size"]
            chunk_rows = wire_rows[start:start + statement["chunk_size"]]
            chunk_manifest = {
                "chunk_index": chunk_index,
                "row_offset": start,
                "row_count": len(chunk_rows),
            }
            if statement["disposition"] == "EXTERNAL_LINKS":
                chunk_manifest["byte_count"] = len(json.dumps(chunk_rows, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
            chunks.append(chunk_manifest)
        manifest = {
            "format": "JSON_ARRAY",
            "schema": {"column_count": len(statement["columns"]), "columns": statement["columns"]},
            "chunks": chunks,
            "total_chunk_count": self._chunk_count(statement),
            "total_row_count": len(statement["rows"]),
            "truncated": bool(statement["truncated"]),
        }
        if statement["disposition"] == "EXTERNAL_LINKS":
            manifest["total_byte_count"] = byte_count
        return manifest

    def _result_chunk(self, statement, chunk_index):
        start = chunk_index * statement["chunk_size"]
        rows = self._wire_rows(statement["rows"][start:start + statement["chunk_size"]])
        total_chunks = self._chunk_count(statement)
        result = {"chunk_index": chunk_index, "row_offset": start, "row_count": len(rows)}
        base = "/api/2.0/sql/statements/%s/result/chunks/" % statement["statement_id"]
        if statement["disposition"] == "INLINE":
            result["data_array"] = rows
        else:
            byte_count = len(json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
            link = {
                "chunk_index": chunk_index,
                "row_offset": start,
                "row_count": len(rows),
                "byte_count": byte_count,
                "expiration": statement["external_expiration"],
                "external_link": "https://results.simulated.invalid/statements/%s/chunks/%s" % (statement["statement_id"], chunk_index),
            }
            if chunk_index + 1 < total_chunks:
                link["next_chunk_index"] = chunk_index + 1
                link["next_chunk_internal_link"] = base + str(chunk_index + 1)
            result["external_links"] = [link]
        if chunk_index + 1 < total_chunks:
            if statement["disposition"] == "INLINE":
                result["next_chunk_index"] = chunk_index + 1
                result["next_chunk_internal_link"] = base + str(chunk_index + 1)
        return result
