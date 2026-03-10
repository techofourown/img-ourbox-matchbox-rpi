#!/usr/bin/env python3
"""Focused tests for pr_batch_big_picture edge cases."""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("pr_batch_big_picture.py")
REPO_ROOT = MODULE_PATH.parent.parent
SPEC = importlib.util.spec_from_file_location("pr_batch_big_picture", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load module spec for {MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PrBatchBigPictureTests(unittest.TestCase):
    def setUp(self) -> None:
        self._original_cwd = Path.cwd()
        os.chdir(REPO_ROOT)

    def tearDown(self) -> None:
        os.chdir(self._original_cwd)
        MODULE.get_repo_slug.cache_clear()

    def test_should_include_review_entry_for_empty_body_actions(self) -> None:
        self.assertTrue(MODULE.should_include_review_entry({"state": "APPROVED", "body": ""}))
        self.assertTrue(
            MODULE.should_include_review_entry({"state": "CHANGES_REQUESTED", "body": ""})
        )
        self.assertFalse(MODULE.should_include_review_entry({"state": "COMMENTED", "body": ""}))

    def test_get_pr_comments_includes_bare_review_actions_and_inline_threads(self) -> None:
        def fake_run_command(cmd: str, check: bool = True, capture_output: bool = True) -> str:
            if "--json comments,reviews" in cmd:
                return json.dumps(
                    {
                        "comments": [
                            {
                                "author": {"login": "issue-user"},
                                "createdAt": "2026-03-10T00:00:01Z",
                                "body": "top-level issue comment",
                                "url": "https://example.test/issue",
                            }
                        ],
                        "reviews": [
                            {
                                "author": {"login": "approver"},
                                "submittedAt": "2026-03-10T00:00:02Z",
                                "body": "",
                                "state": "APPROVED",
                            },
                            {
                                "author": {"login": "requester"},
                                "submittedAt": "2026-03-10T00:00:03Z",
                                "body": "",
                                "state": "CHANGES_REQUESTED",
                            },
                            {
                                "author": {"login": "empty-comment"},
                                "submittedAt": "2026-03-10T00:00:04Z",
                                "body": "",
                                "state": "COMMENTED",
                            },
                            {
                                "author": {"login": "reviewer"},
                                "submittedAt": "2026-03-10T00:00:05Z",
                                "body": "review summary",
                                "state": "COMMENTED",
                            },
                        ],
                    }
                )
            if cmd == "gh repo view --json nameWithOwner":
                return json.dumps({"nameWithOwner": "techofourown/sw-ourbox-os"})
            if "/pulls/999/comments" in cmd:
                return json.dumps(
                    [
                        {
                            "user": {"login": "inline-user"},
                            "created_at": "2026-03-10T00:00:06Z",
                            "body": "inline body",
                            "path": "tools/example.txt",
                            "line": 7,
                            "html_url": "https://example.test/discussion/1",
                        },
                        {
                            "user": {"login": "reply-user"},
                            "created_at": "2026-03-10T00:00:07Z",
                            "body": "reply body",
                            "path": "tools/example.txt",
                            "line": 7,
                            "in_reply_to_id": 12345,
                            "html_url": "https://example.test/discussion/2",
                        },
                    ]
                )
            raise AssertionError(f"Unexpected command: {cmd}")

        with mock.patch.object(MODULE, "run_command", side_effect=fake_run_command):
            MODULE.get_repo_slug.cache_clear()
            comments = MODULE.get_pr_comments(999)

        self.assertEqual([comment["type"] for comment in comments], [
            "issue",
            "review",
            "review",
            "review",
            "review-comment",
            "review-reply",
        ])
        self.assertEqual(comments[1]["state"], "APPROVED")
        self.assertEqual(comments[2]["state"], "CHANGES_REQUESTED")
        self.assertEqual(comments[3]["body"], "review summary")
        self.assertEqual(comments[4]["path"], "tools/example.txt")
        self.assertEqual(comments[5]["inReplyToId"], "12345")

    def test_run_big_picture_reports_excluded_only_prs(self) -> None:
        pr_info = {
            "number": 123,
            "title": "excluded-only fixture",
            "branch": "fixture-branch",
            "body": "",
            "author": "fixture-user",
            "createdAt": "2026-03-10T00:00:00Z",
            "url": "https://example.test/pull/123",
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            output_file = str(Path(tmpdir) / "excluded-only.txt")
            ok = MODULE.run_big_picture(
                pr_info=pr_info,
                files=[],
                excluded_files=["package-lock.json"],
                all_files=["package-lock.json"],
                comments=[
                    {
                        "type": "review",
                        "author": "approver",
                        "createdAt": "2026-03-10T00:00:01Z",
                        "url": "",
                        "body": "",
                        "state": "APPROVED",
                    }
                ],
                checks=[],
                output_file=output_file,
                include_logs=False,
                base_branch="main",
                local_branch="fixture-branch",
            )

            self.assertTrue(ok)
            text = Path(output_file).read_text(encoding="utf-8")

        self.assertIn("# Excluded file list: package-lock.json", text)
        self.assertIn("# All changed files for this PR were excluded from diff output.", text)
        self.assertIn("# PR Number: 123", text)
        self.assertIn("(review, state=APPROVED)", text)
        self.assertIn("(no content)", text)

    def test_create_touched_files_compilation_can_include_deleted_path_source(self) -> None:
        def fake_run_command(cmd: str, check: bool = True, capture_output: bool = True) -> str:
            expected = "git show HEAD:package-lock.json"
            if cmd == expected:
                return '{\n  "name": "fixture"\n}\n'
            raise AssertionError(f"Unexpected command: {cmd}")

        with tempfile.TemporaryDirectory() as tmpdir:
            output_file = str(Path(tmpdir) / "touched.txt")
            with mock.patch.object(MODULE, "run_command", side_effect=fake_run_command):
                ok = MODULE.create_touched_files_compilation(
                    touched_files={"package-lock.json"},
                    touched_file_prs={"package-lock.json": {78}},
                    base_branch="HEAD",
                    selection_requested="78",
                    selection_canonical="78",
                    selected_prs=[78],
                    output_file=output_file,
                )

            self.assertTrue(ok)
            text = Path(output_file).read_text(encoding="utf-8")

        self.assertIn("# File: package-lock.json", text)
        self.assertIn("# Includes all changed paths from the selected PRs", text)
        self.assertIn("# Touched by PRs: 78", text)

    def test_create_round_robin_comparisons_skips_excluded_only_pairs(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            outputs = MODULE.create_round_robin_comparisons(
                processed_prs=[
                    {
                        "info": {
                            "number": 101,
                            "title": "excluded-only left",
                            "body": "",
                            "author": "left-user",
                            "url": "https://example.test/pr/101",
                        },
                        "local_branch": "left-branch",
                        "files": [],
                    },
                    {
                        "info": {
                            "number": 102,
                            "title": "excluded-only right",
                            "body": "",
                            "author": "right-user",
                            "url": "https://example.test/pr/102",
                        },
                        "local_branch": "right-branch",
                        "files": [],
                    },
                ],
                output_dir=tmpdir,
                selection_requested="101-102",
                selection_canonical="101-102",
                selected_prs=[101, 102],
            )

        self.assertEqual(outputs, [])

    def test_checkout_pr_branch_prefers_pr_ref_over_existing_local_branch(self) -> None:
        commands = []

        def fake_run_command(cmd: str, check: bool = True, capture_output: bool = True) -> str:
            commands.append(cmd)
            return ""

        with mock.patch.object(MODULE, "run_command", side_effect=fake_run_command):
            branch = MODULE.checkout_pr_branch({"number": 123, "branch": "patch-1"}, "github")

        self.assertEqual(branch, "pr-123")
        self.assertEqual(
            commands,
            [
                "git fetch github pull/123/head",
                "git checkout -B pr-123 FETCH_HEAD",
            ],
        )


if __name__ == "__main__":
    unittest.main()
