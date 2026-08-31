from __future__ import annotations

import argparse
import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("kunja_helper", str(ROOT / "bin/kunja"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
helper = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[LOADER.name] = helper
SPEC.loader.exec_module(helper)


class EndpointTests(unittest.TestCase):
    def test_normalizes_https_endpoint(self):
        self.assertEqual(
            helper.normalize_endpoint(" https://vikunja.example.test/ "),
            "https://vikunja.example.test",
        )

    def test_rejects_credentials_and_non_https(self):
        for endpoint in ("http://example.test", "https://user:pass@example.test", "not-a-url"):
            with self.subTest(endpoint=endpoint), self.assertRaises(helper.KunjaError):
                helper.normalize_endpoint(endpoint)

    def test_vikunja_auth_error_is_classified(self):
        error = helper.classify_http_error(401)
        self.assertEqual(error.kind, "vikunja-auth")

    def test_api_token_settings_url_uses_instance_root(self):
        self.assertEqual(
            helper.api_token_settings_url("https://vikunja.example.test/"),
            "https://vikunja.example.test/user/settings/api-tokens",
        )

    def test_endpoint_prompt_retries_and_accepts_https_url(self):
        answers = iter(["http://vikunja.example.test", "https://vikunja.example.test/"])
        with mock.patch("builtins.print"):
            endpoint = helper.prompt_endpoint(None, lambda _: next(answers))
        self.assertEqual(endpoint, "https://vikunja.example.test")

    def test_endpoint_argument_skips_prompt(self):
        endpoint = helper.prompt_endpoint(
            "https://vikunja.example.test/",
            lambda _: self.fail("prompt should not be called"),
        )
        self.assertEqual(endpoint, "https://vikunja.example.test")

    def test_endpoint_prompt_reuses_saved_url_as_default(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            helper, "config_path", return_value=Path(directory) / "config.json"
        ):
            helper.atomic_write_json(
                helper.config_path(),
                {"endpoint": "https://saved-vikunja.example.test"},
            )
            self.assertEqual(
                helper.prompt_endpoint(None, lambda _: ""),
                "https://saved-vikunja.example.test",
            )

    def test_yes_no_defaults_to_yes_and_reprompts(self):
        answers = iter(["maybe", "n"])
        with mock.patch("builtins.print"):
            self.assertFalse(helper.ask_yes_no("Open?", input_fn=lambda _: next(answers)))
        self.assertTrue(helper.ask_yes_no("Open?", input_fn=lambda _: ""))

    def test_browser_opener_does_not_use_a_shell(self):
        calls = []

        def runner(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0)

        self.assertTrue(helper.open_browser("https://vikunja.example.test/settings", runner))
        self.assertEqual(calls[0][0], ["xdg-open", "https://vikunja.example.test/settings"])
        self.assertNotIn("shell", calls[0][1])

    def test_configuration_does_not_store_token_when_validation_fails(self):
        args = argparse.Namespace(
            endpoint="https://vikunja.example.test",
            no_open_browser=True,
        )
        with mock.patch.object(helper, "require_secret_tool"), mock.patch.object(
            helper.getpass, "getpass", return_value="tk_test"
        ), mock.patch.object(
            helper, "detect_api_version", side_effect=helper.KunjaError("network", "offline")
        ), mock.patch.object(helper, "store_secret") as store_secret, mock.patch("builtins.print"):
            with self.assertRaises(helper.KunjaError):
                helper.configure(args)
        store_secret.assert_not_called()


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 30, 10, 0, tzinfo=timezone.utc)
        self.credentials = helper.Credentials("vikunja")
        self.config = {
            "endpoint": "https://vikunja.example.test",
            "api_version": "v2",
            "timezone": "Europe/Copenhagen",
        }

    def task(self, task_id, due, *, assignee=7, done=False, priority=0):
        return {
            "id": task_id,
            "index": task_id,
            "identifier": f"OPS-{task_id}",
            "project_id": 4,
            "title": f"Task {task_id}",
            "due_date": due,
            "done": done,
            "priority": priority,
            "assignees": [{"id": assignee}],
            "labels": [{"title": "work", "hex_color": "336699"}],
        }

    def transport(self, endpoint, version, path, credentials, params):
        self.assertEqual(credentials, self.credentials)
        if path == "user":
            return {"id": 7, "username": "test-user"}, {}
        if path == "projects":
            return {"items": [{"id": 4, "title": "Operations"}], "total_pages": 1}, {}
        if path == "tasks":
            self.assertIn("assignees in", params["filter"])
            tasks = [
                self.task(1, helper.iso_utc(self.now - timedelta(hours=2)), priority=3),
                self.task(2, helper.iso_utc(self.now + timedelta(hours=1))),
                self.task(3, helper.iso_utc(self.now + timedelta(days=20))),
                self.task(4, "0001-01-01T00:00:00Z"),
                self.task(6, helper.iso_utc(self.now + timedelta(hours=4)), done=True),
            ]
            return {"items": tasks, "total_pages": 1}, {}
        raise AssertionError(path)

    def test_fetches_filters_and_normalizes_tasks(self):
        document = helper.fetch_document(
            self.config,
            self.credentials,
            horizon_days=14,
            max_tasks=50,
            now=self.now,
            transport=self.transport,
        )
        self.assertEqual([task["id"] for task in document["tasks"]], [1, 2])
        self.assertEqual(document["overdue_count"], 1)
        self.assertEqual(document["tasks"][0]["project_title"], "Operations")
        self.assertEqual(document["tasks"][1]["frontend_url"], "https://vikunja.example.test/tasks/2")

    def test_api_headers_only_contain_vikunja_authentication(self):
        self.assertEqual(
            set(helper.api_headers(self.credentials)),
            {"Accept", "Authorization", "User-Agent"},
        )
        self.assertEqual(
            helper.api_headers(self.credentials)["Authorization"],
            "Bearer vikunja",
        )

    def test_v1_pagination_shape(self):
        calls = []

        def transport(endpoint, version, path, credentials, params):
            calls.append(params["page"])
            page = params["page"]
            return ([{"id": page}] if page <= 2 else []), {"x-pagination-total-pages": "2"}

        items = helper.fetch_all_pages(
            self.config["endpoint"], "v1", "projects", self.credentials, {"per_page": 1}, transport
        )
        self.assertEqual([item["id"] for item in items], [1, 2])
        self.assertEqual(calls, [1, 2])

    def test_api_detection_prefers_v2_and_falls_back_only_on_404(self):
        def v2_transport(endpoint, version, path, credentials, params):
            return {"version": "2.4.0"}, {}

        self.assertEqual(
            helper.detect_api_version(self.config["endpoint"], self.credentials, v2_transport),
            "v2",
        )
        calls = []

        def fallback_transport(endpoint, version, path, credentials, params):
            calls.append(version)
            if version == "v2":
                raise helper.KunjaError("not-found", "missing", 404)
            return {"version": "1.0.0"}, {}

        self.assertEqual(
            helper.detect_api_version(self.config["endpoint"], self.credentials, fallback_transport),
            "v1",
        )
        self.assertEqual(calls, ["v2", "v1"])

    def test_cached_result_becomes_stale(self):
        cached = {"schema_version": 1, "status": "ok", "tasks": [{"id": 1}]}
        result = helper.error_document(helper.KunjaError("network", "offline"), cached)
        self.assertEqual(result["status"], "stale")
        self.assertEqual(result["tasks"], [{"id": 1}])

    def test_unconfigured_result_does_not_reuse_cached_tasks(self):
        cached = {"schema_version": 1, "status": "ok", "tasks": [{"id": 1}]}
        result = helper.error_document(helper.KunjaError("unconfigured", "setup"), cached)
        self.assertEqual(result["status"], "unconfigured")
        self.assertEqual(result["tasks"], [])

    def test_project_create_options_are_writable_flattened_and_sorted(self):
        projects = [
            {
                "id": 2,
                "title": "Parent",
                "max_permission": 1,
                "child_projects": [
                    {"id": 3, "title": "Child", "max_permission": 2},
                    {"id": 4, "title": "Read only", "max_permission": 0},
                ],
            },
            {"id": 5, "title": "Archived", "max_permission": 2, "is_archived": True},
        ]
        self.assertEqual(
            helper.project_create_options(projects),
            [
                {"id": 2, "title": "Parent", "label": "Parent"},
                {"id": 3, "title": "Child", "label": "Parent / Child"},
            ],
        )

    def test_create_task_posts_task_and_assignee(self):
        calls = []

        def transport(endpoint, version, path, credentials, params, **kwargs):
            calls.append((path, params, kwargs))
            if path == "projects/4/tasks":
                return {"id": 91, "identifier": "OPS-91", "title": "Ship Kunja"}, {}
            if path == "tasks/91/assignees/bulk":
                return {}, {}
            raise AssertionError(path)

        result = helper.create_task_document(
            self.config,
            self.credentials,
            {
                "title": " Ship Kunja ",
                "description": "Release notes",
                "project_id": 4,
                "assignee_id": 7,
                "assignee_label": "Alex Employee",
                "due_date": "2026-09-01T14:30:00Z",
                "priority": 4,
            },
            transport,
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["task"]["frontend_url"], "https://vikunja.example.test/tasks/91")
        self.assertEqual(calls[0][0], "projects/4/tasks")
        self.assertEqual(calls[0][1], {"format": "markdown"})
        self.assertEqual(calls[0][2]["method"], "POST")
        self.assertEqual(calls[0][2]["body"]["due_date"], "2026-09-01T14:30:00Z")
        self.assertEqual(calls[1][0], "tasks/91/assignees/bulk")
        self.assertEqual(calls[1][2]["method"], "PUT")
        self.assertEqual(calls[1][2]["body"], {"assignees": [{"id": 7}]})
        self.assertEqual(result["task"]["assignee_label"], "Alex Employee")

    def test_assignee_failure_keeps_created_task(self):
        def transport(endpoint, version, path, credentials, params, **kwargs):
            if path == "projects/4/tasks":
                return {"id": 92, "title": "Created anyway"}, {}
            raise helper.KunjaError("vikunja-permission", "Assignment denied.", 403)

        result = helper.create_task_document(
            self.config,
            self.credentials,
            {
                "title": "Created anyway",
                "project_id": 4,
                "assignee_id": 7,
                "due_date": "2026-09-01T14:30:00Z",
                "priority": 0,
            },
            transport,
        )
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["task"]["id"], 92)
        self.assertIn("assignee", result["message"])

    def test_unassigned_replaces_any_default_assignee_with_empty_set(self):
        calls = []

        def transport(endpoint, version, path, credentials, params, **kwargs):
            calls.append((path, kwargs))
            if path == "projects/4/tasks":
                return {"id": 93, "title": "Nobody owns this"}, {}
            if path == "tasks/93/assignees/bulk":
                return {"assignees": []}, {}
            raise AssertionError(path)

        result = helper.create_task_document(
            self.config,
            self.credentials,
            {
                "title": "Nobody owns this",
                "project_id": 4,
                "assignee_id": None,
                "assignee_label": "Unassigned",
                "due_date": "2026-09-01T14:30:00Z",
                "priority": 0,
            },
            transport,
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(calls[1][0], "tasks/93/assignees/bulk")
        self.assertEqual(calls[1][1]["body"], {"assignees": []})

    def test_create_task_requires_v2_and_valid_required_fields(self):
        with self.assertRaises(helper.KunjaError) as invalid:
            helper.validate_create_payload({"title": "", "project_id": 4})
        self.assertEqual(invalid.exception.kind, "invalid-config")
        with self.assertRaises(helper.KunjaError) as unsupported:
            helper.create_task_document(
                dict(self.config, api_version="v1"),
                self.credentials,
                {},
            )
        self.assertEqual(unsupported.exception.kind, "unsupported-api")


class ReminderTests(unittest.TestCase):
    def test_reminder_is_sent_once_per_task_and_due_value(self):
        now = datetime(2026, 8, 30, 10, 0, tzinfo=timezone.utc)
        task = {
            "id": 42,
            "title": "Rotate service token",
            "project_title": "Operations",
            "relative_due": "Due in 30m",
            "due_at": helper.iso_utc(now + timedelta(minutes=30)),
            "frontend_url": "https://vikunja.example.test/tasks/42",
        }
        calls = []

        def runner(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            helper, "reminder_path", return_value=Path(directory) / "reminders.json"
        ):
            self.assertEqual(helper.send_due_notifications([task], 60, now, runner), 1)
            self.assertEqual(helper.send_due_notifications([task], 60, now, runner), 0)
            changed = dict(task, due_at=helper.iso_utc(now + timedelta(minutes=45)))
            self.assertEqual(helper.send_due_notifications([changed], 60, now, runner), 1)

        self.assertEqual(len(calls), 2)
        flattened = " ".join(calls[0])
        self.assertNotIn("client-secret", flattened)
        self.assertIn("/tasks/42", flattened)

    def test_overdue_task_does_not_notify(self):
        now = datetime(2026, 8, 30, 10, 0, tzinfo=timezone.utc)
        task = {
            "id": 7,
            "title": "Already late",
            "project_title": "Ops",
            "relative_due": "Overdue by 1h",
            "due_at": helper.iso_utc(now - timedelta(hours=1)),
            "frontend_url": "https://vikunja.example.test/tasks/7",
        }
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            helper, "reminder_path", return_value=Path(directory) / "reminders.json"
        ):
            self.assertEqual(helper.send_due_notifications([task], 60, now), 0)

    def test_missing_notification_binary_does_not_break_sync_state(self):
        now = datetime(2026, 8, 30, 10, 0, tzinfo=timezone.utc)
        task = {
            "id": 8,
            "title": "Still watch tasks",
            "project_title": "Ops",
            "relative_due": "Due in 30m",
            "due_at": helper.iso_utc(now + timedelta(minutes=30)),
            "frontend_url": "https://vikunja.example.test/tasks/8",
        }

        def missing_runner(*args, **kwargs):
            raise FileNotFoundError("omarchy-notification-send")

        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            helper, "reminder_path", return_value=Path(directory) / "reminders.json"
        ):
            self.assertEqual(helper.send_due_notifications([task], 60, now, missing_runner), 0)


if __name__ == "__main__":
    unittest.main()
