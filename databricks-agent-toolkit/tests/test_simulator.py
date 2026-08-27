import contextlib
import io
import json
import os
import socket
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[1]

from simulator.cli import _extract_global_flags, main, render_text
from simulator.core import Simulator, StateStore, load_json_argument
from simulator.sql_engine import SQLExecutionError, validate_read_only


class SimulatorTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state_dir = Path(self.temp.name) / ".sim-state"
        self.store = StateStore(PROJECT_ROOT, self.state_dir)
        self.sim = Simulator(self.store)

    def tearDown(self):
        self.temp.cleanup()

    def run_ok(self, *args):
        payload, code = self.sim.execute(list(args))
        self.assertEqual(code, 0, payload)
        self.assertTrue(payload["_simulated"])
        return payload

    def run_error(self, expected_code, *args):
        payload, code = self.sim.execute(list(args))
        self.assertNotEqual(code, 0, payload)
        self.assertEqual(payload["error_code"], expected_code)
        self.assertTrue(payload["_simulated"])
        return payload, code

    def api_post(self, body):
        return self.sim.execute(["api", "post", "/api/2.0/sql/statements", "--json", json.dumps(body)])

    def api_get(self, path):
        return self.sim.execute(["api", "get", path])

    def async_body(self, statement="SELECT 1 AS one", **updates):
        body = {"warehouse_id": "wh-sim-001", "statement": statement, "wait_timeout": "0s"}
        body.update(updates)
        return body

    def finish(self, statement_id):
        first, code = self.api_get("/api/2.0/sql/statements/%s" % statement_id)
        self.assertEqual(code, 0)
        self.assertEqual(first["status"]["state"], "RUNNING")
        second, code = self.api_get("/api/2.0/sql/statements/%s" % statement_id)
        self.assertEqual(code, 0)
        return second


class BasicCommandTests(SimulatorTestCase):
    def test_version_quickstart_and_notice(self):
        self.assertIn("sim.1", self.run_ok("version")["version"])
        guide = self.run_ok("quickstart")["guide"]
        self.assertIn("'@examples/statement-inline.json'", guide[1])

    def test_current_user_attributes(self):
        payload = self.run_ok("current-user", "me", "--attributes", "id,userName")
        self.assertEqual(payload["userName"], "agent@simulated.invalid")
        self.assertNotIn("displayName", payload)

    def test_auth_profiles_is_synthetic(self):
        payload = self.run_ok("auth", "profiles", "--host", "https://real.example")
        self.assertEqual(payload["profiles"][0]["name"], "SIMULATED")
        self.assertIn("--host", payload["filters_ignored_offline"])

    def test_warehouse_get_start_stop(self):
        self.assertEqual(self.run_ok("warehouses", "get", "wh-sim-002")["state"], "STOPPED")
        self.assertEqual(self.run_ok("warehouses", "start", "wh-sim-002")["state"], "RUNNING")
        self.assertEqual(self.run_ok("warehouses", "stop", "wh-sim-002")["state"], "STOPPED")

    def test_warehouse_list_limit(self):
        payload = self.run_ok("warehouses", "list", "--limit", "1")
        self.assertEqual(len(payload["warehouses"]), 1)

    def test_cluster_get_start_delete(self):
        self.assertEqual(self.run_ok("clusters", "get", "cluster-sim-002")["state"], "TERMINATED")
        self.assertEqual(self.run_ok("clusters", "start", "cluster-sim-002")["state"], "RUNNING")
        self.assertEqual(self.run_ok("clusters", "delete", "cluster-sim-002")["state"], "TERMINATED")

    def test_job_run_poll_and_cancel(self):
        created = self.run_ok("jobs", "run-now", "101", "--no-wait")
        run_id = str(created["run_id"])
        self.assertEqual(created["state"]["life_cycle_state"], "PENDING")
        self.assertEqual(self.run_ok("jobs", "get-run", run_id)["state"]["life_cycle_state"], "RUNNING")
        canceled = self.run_ok("jobs", "cancel-run", run_id, "--no-wait")
        self.assertEqual(canceled["state"]["life_cycle_state"], "TERMINATING")
        final = self.run_ok("jobs", "get-run", run_id)
        self.assertEqual(final["state"]["result_state"], "CANCELED")

    def test_job_idempotency_token_replays(self):
        first = self.run_ok("jobs", "run-now", "101", "--no-wait", "--idempotency-token", "same-token")
        second = self.run_ok("jobs", "run-now", "101", "--no-wait", "--idempotency-token", "same-token")
        self.assertEqual(first["run_id"], second["run_id"])
        self.assertTrue(second["idempotent_replay"])
        cross_job = self.run_ok("jobs", "run-now", "102", "--no-wait", "--idempotency-token", "same-token")
        self.assertEqual(first["run_id"], cross_job["run_id"])
        self.run_error("INVALID_PARAMETER_VALUE", "jobs", "run-now", "101", "--idempotency-token", "x" * 65)

    def test_completed_job_cannot_be_retroactively_canceled(self):
        created = self.run_ok("jobs", "run-now", "101")
        unchanged = self.run_ok("jobs", "cancel-run", str(created["run_id"]))
        self.assertEqual(unchanged["state"]["result_state"], "SUCCESS")

    def test_job_list_name_filter(self):
        result = self.run_ok("jobs", "list", "--name", "synthetic sales summary")
        self.assertEqual([102], [job["job_id"] for job in result["jobs"]])

    def test_query_crud_and_update_mask(self):
        body = {"display_name": "Created", "query_text": "SELECT 1 AS one", "warehouse_id": "wh-sim-001"}
        created = self.run_ok("queries", "create", "--json", json.dumps(body))
        query_id = created["id"]
        updated = self.run_ok("queries", "update", query_id, "display_name", "--json", json.dumps({"display_name": "Updated"}))
        self.assertEqual(updated["display_name"], "Updated")
        self.assertEqual(self.run_ok("queries", "get", query_id)["id"], query_id)
        self.assertTrue(self.run_ok("queries", "delete", query_id)["deleted"])
        self.run_error("RESOURCE_DOES_NOT_EXIST", "queries", "get", query_id)

    def test_saved_query_rejects_write_sql(self):
        body = {"display_name": "Unsafe", "query_text": "DELETE FROM main.analytics.daily_sales", "warehouse_id": "wh-sim-001"}
        self.run_error("READ_ONLY_VIOLATION", "queries", "create", "--json", json.dumps(body))


class ResourceCommandTests(SimulatorTestCase):
    def test_unity_catalog_list_and_get_grammar(self):
        self.assertEqual(self.run_ok("catalogs", "get", "main")["name"], "main")
        self.assertEqual(self.run_ok("schemas", "list", "main")["schemas"][0]["full_name"], "main.analytics")
        self.assertEqual(self.run_ok("tables", "get", "samples.nyctaxi.trips")["name"], "trips")
        self.assertEqual(self.run_ok("volumes", "read", "main.analytics.agent_files")["name"], "agent_files")

    def test_nonexistent_resource(self):
        self.run_error("RESOURCE_DOES_NOT_EXIST", "catalogs", "get", "missing")

    def test_rejects_hallucinated_resource_aliases(self):
        self.run_error("UNKNOWN_COMMAND", "catalogs", "read", "main")
        self.run_error("UNKNOWN_COMMAND", "volumes", "get", "main.analytics.agent_files")

    def test_command_specific_flags(self):
        self.run_error("UNKNOWN_FLAG", "catalogs", "get", "main", "--omit-columns")
        omitted = self.run_ok("tables", "list", "samples", "nyctaxi", "--omit-columns")
        self.assertNotIn("columns", omitted["tables"][0])
        self.run_error("UNKNOWN_FLAG", "warehouses", "get", "wh-sim-001", "--no-wait")
        self.run_error("UNKNOWN_FLAG", "clusters", "get", "cluster-sim-001", "--timeout", "1m")

    def test_workspace_directory_lists_children(self):
        result = self.run_ok("workspace", "list", "/Shared")
        self.assertEqual(["/Shared/agent-lab"], [item["path"] for item in result["objects"]])
        notebook = self.run_ok("workspace", "list", "/Shared/agent-lab/quality_check")
        self.assertEqual("NOTEBOOK", notebook["objects"][0]["object_type"])

    def test_fs_ls_requires_dbfs_scheme(self):
        result = self.run_ok("fs", "ls", "dbfs:/FileStore", "--absolute")
        self.assertEqual(2, len(result["files"]))
        self.run_error("INVALID_PARAMETER_VALUE", "fs", "ls", "/FileStore")


class StatementExecutionTests(SimulatorTestCase):
    def test_api_flags_can_precede_path(self):
        body = json.dumps({"warehouse_id": "wh-sim-001", "statement": "SELECT 1 AS one"})
        payload, code = self.sim.execute([
            "api", "post", "--json", body, "/api/2.0/sql/statements",
        ])
        self.assertEqual(code, 0, payload)
        self.assertEqual(payload["status"]["state"], "SUCCEEDED")

    def test_default_wait_returns_synchronous_success(self):
        payload, code = self.api_post({"warehouse_id": "wh-sim-001", "statement": "SELECT 1 AS one"})
        self.assertEqual(code, 0)
        self.assertEqual(payload["status"]["state"], "SUCCEEDED")
        self.assertEqual(payload["result"]["data_array"], [["1"]])

    def test_async_pending_running_succeeded(self):
        created, code = self.api_post(self.async_body())
        self.assertEqual(code, 0)
        self.assertEqual(created["status"]["state"], "PENDING")
        final = self.finish(created["statement_id"])
        self.assertEqual(final["status"]["state"], "SUCCEEDED")
        self.assertEqual(final["manifest"]["total_row_count"], 1)

    def test_named_typed_parameters(self):
        body = {
            "warehouse_id": "wh-sim-001",
            "statement": "SELECT :region AS region, :minimum AS minimum, :ok AS ok",
            "parameters": [
                {"name": "region", "value": "East", "type": "STRING"},
                {"name": "minimum", "value": "1000", "type": "INT"},
                {"name": "ok", "value": "true", "type": "BOOLEAN"},
            ],
        }
        payload, code = self.api_post(body)
        self.assertEqual(code, 0)
        self.assertEqual(payload["result"]["data_array"], [["East", "1000", "true"]])
        self.assertEqual(["STRING", "INT", "BOOLEAN"], [c["type_name"] for c in payload["manifest"]["schema"]["columns"]])

    def test_missing_parameter_is_http_400_nonzero(self):
        payload, code = self.api_post(self.async_body("SELECT :missing AS value"))
        self.assertEqual(code, 1)
        self.assertEqual(payload["_http"]["status_code"], 400)
        self.assertEqual(payload["error_code"], "UNBOUND_SQL_PARAMETER")

    def test_read_only_enforcement_is_http_400_nonzero(self):
        for statement in (
            "DELETE FROM main.analytics.daily_sales",
            "CREATE TABLE x (id INT)",
            "SELECT 1; DROP TABLE x",
            "WITH x AS (SELECT 1) UPDATE main.analytics.daily_sales SET total=0",
        ):
            with self.subTest(statement=statement):
                payload, code = self.api_post(self.async_body(statement))
                self.assertEqual(code, 1)
                self.assertEqual(payload["_http"]["status_code"], 400)
                self.assertIn(payload["error_code"], ("READ_ONLY_VIOLATION", "MULTI_STATEMENT_UNSUPPORTED"))

    def test_execution_failure_is_terminal_inside_http_200(self):
        created, code = self.api_post(self.async_body("/* SIMULATE:FAIL */ SELECT 1"))
        self.assertEqual(code, 0)
        failed = self.finish(created["statement_id"])
        self.assertEqual(failed["_http"]["status_code"], 200)
        self.assertEqual(failed["status"]["state"], "FAILED")
        self.assertEqual(failed["status"]["error"]["error_code"], "SIMULATED_EXECUTION_ERROR")

    def test_cancel_then_poll(self):
        created, code = self.api_post(self.async_body("SELECT * FROM samples.nyctaxi.trips"))
        self.assertEqual(code, 0)
        statement_id = created["statement_id"]
        canceled, code = self.sim.execute(["api", "post", "/api/2.0/sql/statements/%s/cancel" % statement_id])
        self.assertEqual(code, 0)
        self.assertNotIn("status", canceled)
        polled, code = self.api_get("/api/2.0/sql/statements/%s" % statement_id)
        self.assertEqual(code, 0)
        self.assertEqual(polled["status"]["state"], "CANCELED")

    def test_inline_chunks_and_manifest(self):
        created, code = self.api_post(self.async_body("SELECT * FROM samples.nyctaxi.trips"))
        final = self.finish(created["statement_id"])
        self.assertEqual(final["manifest"]["total_chunk_count"], 3)
        self.assertEqual(len(final["manifest"]["chunks"]), 3)
        self.assertNotIn("byte_count", final["manifest"]["chunks"][0])
        self.assertNotIn("total_byte_count", final["manifest"])
        self.assertEqual(final["result"]["next_chunk_index"], 1)
        chunk, code = self.api_get(final["result"]["next_chunk_internal_link"])
        self.assertEqual(code, 0)
        self.assertEqual(chunk["chunk_index"], 1)
        self.assertEqual(chunk["data_array"][0][0], "3")

    def test_external_links_are_safe_short_lived_and_link_chained(self):
        created, code = self.api_post(self.async_body(
            "SELECT * FROM samples.nyctaxi.trips", disposition="EXTERNAL_LINKS"
        ))
        final = self.finish(created["statement_id"])
        link = final["result"]["external_links"][0]
        self.assertTrue(link["external_link"].startswith("https://results.simulated.invalid/"))
        expires = datetime.fromisoformat(link["expiration"].replace("Z", "+00:00"))
        remaining = (expires - datetime.now(timezone.utc)).total_seconds()
        self.assertGreater(remaining, 0)
        self.assertLessEqual(remaining, 15 * 60)
        self.assertEqual(link["next_chunk_index"], 1)
        self.assertNotIn("next_chunk_index", final["result"])
        self.assertIn("byte_count", final["manifest"]["chunks"][0])
        self.assertIn("total_byte_count", final["manifest"])

    def test_row_limit_sets_truncated(self):
        created, code = self.api_post(self.async_body(
            "SELECT * FROM samples.nyctaxi.trips", row_limit=3
        ))
        final = self.finish(created["statement_id"])
        self.assertTrue(final["manifest"]["truncated"])
        self.assertEqual(final["manifest"]["total_row_count"], 3)

    def test_byte_limit_can_produce_zero_row_external_result(self):
        created, code = self.api_post(self.async_body(
            "SELECT * FROM samples.nyctaxi.trips", byte_limit=1, disposition="EXTERNAL_LINKS"
        ))
        final = self.finish(created["statement_id"])
        self.assertEqual(final["manifest"]["total_row_count"], 0)
        self.assertEqual(final["result"]["external_links"], [])
        self.assertTrue(final["manifest"]["truncated"])

    def test_chunk_before_terminal_is_http_409(self):
        created, code = self.api_post(self.async_body("SELECT * FROM samples.nyctaxi.trips"))
        payload, code = self.api_get("/api/2.0/sql/statements/%s/result/chunks/0" % created["statement_id"])
        self.assertEqual(code, 1)
        self.assertEqual(payload["_http"]["status_code"], 409)

    def test_unknown_api_route_is_http_404_and_nonzero(self):
        payload, code = self.api_get("/api/2.0/unknown")
        self.assertEqual(code, 1)
        self.assertEqual(payload["_http"]["status_code"], 404)

    def test_stopped_warehouse_is_http_409(self):
        payload, code = self.api_post({"warehouse_id": "wh-sim-002", "statement": "SELECT 1"})
        self.assertEqual(code, 1)
        self.assertEqual(payload["_http"]["status_code"], 409)

    def test_wait_timeout_validation_and_slow_cancel(self):
        payload, code = self.api_post({"warehouse_id": "wh-sim-001", "statement": "SELECT 1", "wait_timeout": "2s"})
        self.assertEqual(code, 1)
        self.assertEqual(payload["error_code"], "INVALID_PARAMETER_VALUE")
        slow, code = self.api_post({
            "warehouse_id": "wh-sim-001",
            "statement": "/* SIMULATE:SLOW */ SELECT 1",
            "wait_timeout": "5s",
            "on_wait_timeout": "CANCEL",
        })
        self.assertEqual(code, 0)
        self.assertEqual(slow["status"]["state"], "CANCELED")

    def test_query_history_tracks_statement(self):
        result, code = self.api_post({"warehouse_id": "wh-sim-001", "statement": "SELECT 1"})
        history = self.run_ok("query-history", "list", "--include-metrics")
        self.assertEqual(history["res"][0]["statement_id"], result["statement_id"])
        self.assertEqual(history["res"][0]["status"], "SUCCEEDED")


class SafetyAndInterfaceTests(SimulatorTestCase):
    def test_reset_overwrites_only_state_file(self):
        self.run_ok("warehouses", "stop", "wh-sim-001")
        sentinel = self.state_dir / "keep-me.txt"
        sentinel.write_text("sentinel", encoding="utf-8")
        reset = self.run_ok("sim", "reset")
        self.assertTrue(reset["reset"])
        self.assertTrue(sentinel.exists())
        self.assertEqual(self.run_ok("warehouses", "get", "wh-sim-001")["state"], "RUNNING")

    def test_json_at_file(self):
        body = load_json_argument("@" + str(PROJECT_ROOT / "examples" / "statement-parameterized.json"))
        self.assertIn("parameters", body)

    def test_sql_strings_and_comments_do_not_trigger_write_keyword(self):
        self.assertTrue(validate_read_only("SELECT 'delete drop update' AS harmless -- DELETE\n"))
        with self.assertRaises(SQLExecutionError):
            validate_read_only("SELECT 1; DELETE FROM x")

    def test_no_network_even_when_socket_would_fail(self):
        with mock.patch.object(socket, "create_connection", side_effect=AssertionError("network attempted")):
            self.run_ok("warehouses", "list")
            payload, code = self.api_post({"warehouse_id": "wh-sim-001", "statement": "SELECT 1"})
            self.assertEqual(code, 0)

    def test_global_flag_parser_and_clean_invalid_output(self):
        cleaned, flags = _extract_global_flags(["warehouses", "list", "-o", "json", "-p", "ANY"])
        self.assertEqual(cleaned, ["warehouses", "list"])
        self.assertEqual(flags["profile"], "ANY")
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(["warehouses", "list", "-o", "yaml"])
        self.assertEqual(code, 2)
        self.assertIn("INVALID_ARGUMENT", stdout.getvalue())

    def test_json_output_round_trips_unicode_on_legacy_windows_encoding(self):
        expected = "München 東京 🚀"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(["version", "--profile", expected, "-o", "json"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(stdout.getvalue())["_simulation_profile"], expected)
        self.assertIn("\\u6771", stdout.getvalue())

    def test_text_renderer_is_labeled_and_tabular(self):
        payload = self.run_ok("warehouses", "list", "--limit", "1")
        rendered = render_text(payload)
        self.assertTrue(rendered.startswith("[SIMULATED]"))
        self.assertIn("name", rendered.splitlines()[1])

    def test_wrapper_json_smoke(self):
        command = [
            "powershell.exe", "-NoProfile", "-File",
            str(PROJECT_ROOT / "databricks-sim.ps1"), "version", "-o", "json",
        ]
        completed = subprocess.run(command, cwd=str(PROJECT_ROOT), capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertTrue(json.loads(completed.stdout)["_simulated"])

    def test_wrapper_at_file_json_is_reliable(self):
        command = [
            "powershell.exe", "-NoProfile", "-File", str(PROJECT_ROOT / "databricks-sim.ps1"),
            "api", "post", "/api/2.0/sql/statements", "--json", "@examples/statement-parameterized.json", "-o", "json",
        ]
        completed = subprocess.run(command, cwd=str(PROJECT_ROOT), capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["status"]["state"], "SUCCEEDED")
        self.assertEqual(payload["_http"]["status_code"], 200)

    def test_state_is_project_local_by_default(self):
        default_store = StateStore(PROJECT_ROOT)
        self.assertEqual(default_store.state_dir, PROJECT_ROOT / ".sim-state")


if __name__ == "__main__":
    unittest.main()
