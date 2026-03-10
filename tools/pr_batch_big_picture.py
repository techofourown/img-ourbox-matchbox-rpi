#!/usr/bin/env python3
"""
pr_batch_big_picture - Automate diff generation for ranges of pull requests

This tool automates the process of creating git diffs for consecutive
pull requests, showing only the changes made in each PR, and collecting
all comments made on the pull requests.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime
from functools import lru_cache
from itertools import combinations
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple


class SelectionParseError(ValueError):
    """Raised when a PR selection string cannot be parsed."""


def run_command(cmd: str, check: bool = True, capture_output: bool = True) -> str:
    """Run a shell command and return the result."""
    result = subprocess.run(
        cmd,
        shell=True,
        check=check,
        capture_output=capture_output,
        text=True,
    )
    return result.stdout.strip() if capture_output else ""


@lru_cache(maxsize=1)
def get_repo_slug() -> str:
    """Return the current GitHub repository slug."""
    repo_info = run_command("gh repo view --json nameWithOwner")
    data = json.loads(repo_info)
    name_with_owner = data.get("nameWithOwner") or ""
    if not name_with_owner:
        raise KeyError("Missing nameWithOwner in gh repo view output")
    return name_with_owner


def parse_pr_selection(selection: str) -> List[int]:
    """Parse a selection string into a sorted list of unique PR numbers."""
    original = selection
    trimmed = selection.strip()
    if not trimmed:
        raise SelectionParseError(
            "Invalid PR selection: empty input. "
            "Expected format like '123-130,135,140-142'."
        )

    segments = [segment.strip() for segment in trimmed.split(",")]
    if any(segment == "" for segment in segments):
        raise SelectionParseError(
            f"Invalid PR selection segment '' in '{original}'. "
            "Expected format like '123-130,135,140-142'."
        )

    selected: Set[int] = set()
    for segment in segments:
        cleaned = re.sub(r"\s+", "", segment)
        if not cleaned:
            raise SelectionParseError(
                f"Invalid PR selection segment '{segment}' in '{original}'. "
                "Expected format like '123-130,135,140-142'."
            )

        parts = cleaned.split("-")
        if len(parts) == 1:
            number = _parse_pr_token(parts[0], original)
            selected.add(number)
        elif len(parts) == 2:
            start = _parse_pr_token(parts[0], original)
            end = _parse_pr_token(parts[1], original)
            if start > end:
                raise SelectionParseError(
                    f"Invalid PR range '{segment}' in '{original}': start must be <= end. "
                    "Expected format like '123-130,135,140-142'."
                )
            for number in range(start, end + 1):
                selected.add(number)
        else:
            raise SelectionParseError(
                f"Invalid PR selection segment '{segment}' in '{original}'. "
                "Expected format like '123-130,135,140-142'."
            )

    if not selected:
        raise SelectionParseError(
            f"Invalid PR selection '{original}': no PRs parsed. "
            "Expected format like '123-130,135,140-142'."
        )

    return sorted(selected)


def _parse_pr_token(token: str, original: str) -> int:
    cleaned = token.strip()
    if cleaned.startswith("#"):
        cleaned = cleaned[1:]
    if cleaned == "" or not cleaned.isdigit():
        raise SelectionParseError(
            f"Invalid PR selection token '{token}' in '{original}'. "
            "Expected format like '123-130,135,140-142'."
        )
    number = int(cleaned)
    if number <= 0:
        raise SelectionParseError(
            f"Invalid PR selection token '{token}' in '{original}': "
            "PR numbers must be positive. "
            "Expected format like '123-130,135,140-142'."
        )
    return number


def format_pr_selection(prs: List[int]) -> str:
    """Format a sorted list of PR numbers into a canonical selection string."""
    if not prs:
        return ""

    normalized = sorted(set(prs))
    ranges: List[Tuple[int, int]] = []
    start = normalized[0]
    prev = normalized[0]

    for number in normalized[1:]:
        if number == prev + 1:
            prev = number
            continue
        ranges.append((start, prev))
        start = number
        prev = number
    ranges.append((start, prev))

    parts: List[str] = []
    for range_start, range_end in ranges:
        if range_start == range_end:
            parts.append(str(range_start))
        else:
            parts.append(f"{range_start}-{range_end}")
    return ",".join(parts)


def build_selection_tag(selected_prs: List[int], selection_canonical: str) -> str:
    selection_hash = hashlib.sha1(selection_canonical.encode("utf-8")).hexdigest()[:8]
    if not selected_prs:
        return f"0prs-{selection_hash}"
    min_pr = min(selected_prs)
    max_pr = max(selected_prs)
    return f"{min_pr}-{max_pr}-{len(selected_prs)}prs-{selection_hash}"


def format_pr_list_preview(prs: List[int], max_items: int = 20, edge_items: int = 5) -> str:
    if len(prs) <= max_items:
        return ", ".join(str(pr) for pr in prs)
    head = ", ".join(str(pr) for pr in prs[:edge_items])
    tail = ", ".join(str(pr) for pr in prs[-edge_items:])
    return f"{head} ... {tail}"


def selection_header_lines(
    selection_requested: str, selection_canonical: str, selected_prs: List[int]
) -> List[str]:
    lines = [
        f"# PR selection (requested): {selection_requested}",
        f"# PR selection (canonical): {selection_canonical}",
    ]
    if selected_prs:
        if len(selected_prs) <= 20:
            expanded = ", ".join(str(pr) for pr in selected_prs)
            lines.append(f"# Expanded PRs (count={len(selected_prs)}): {expanded}")
        else:
            preview = format_pr_list_preview(selected_prs)
            lines.append(
                f"# Expanded PRs: count={len(selected_prs)} min={min(selected_prs)} "
                f"max={max(selected_prs)} preview={preview}"
            )
    else:
        lines.append("# Expanded PRs: count=0")
    return lines


def check_current_branch(expected_branch: str) -> None:
    """Ensure we're starting from the expected base branch."""
    current_branch = run_command("git branch --show-current")
    if current_branch != expected_branch:
        print(
            f"Error: Currently on branch '{current_branch}'. "
            f"This tool requires starting from '{expected_branch}' branch."
        )
        sys.exit(1)
    print(f"✓ Starting from {expected_branch} branch")


def checkout_base_branch(base_branch: str) -> None:
    """Checkout the base branch."""
    print(f"Checking out {base_branch} branch...")
    run_command(f"git checkout {shlex.quote(base_branch)}")
    print(f"✓ Checked out {base_branch} branch")


def fetch_remote_branches(remote: str) -> None:
    """Fetch latest remote branches."""
    print(f"Fetching remote branches from {remote}...")
    run_command(f"git fetch {shlex.quote(remote)} --prune --tags")
    print("✓ Fetched remote branches")


def get_pr_info(pr_number: int) -> Dict[str, str]:
    """Get branch name, title, and metadata for a specific PR."""
    pr_info = run_command(
        "gh pr view "
        f"{pr_number} "
        "--json headRefName,title,baseRefName,body,author,createdAt,url"
    )
    data = json.loads(pr_info)

    return {
        "number": pr_number,
        "branch": data["headRefName"],
        "title": data["title"],
        "base": data["baseRefName"],
        "body": data.get("body") or "",
        "author": (data.get("author") or {}).get("login") or "unknown",
        "createdAt": data.get("createdAt") or "",
        "url": data.get("url") or "",
    }


def get_pr_changed_files(pr_number: int) -> List[str]:
    """Get list of changed files for a specific PR."""
    files_json = run_command(f"gh pr view {pr_number} --json files")
    data = json.loads(files_json)
    return [file_info["path"] for file_info in data.get("files", [])]


def normalize_comment_entry(comment: Dict[str, Any], comment_type: str) -> Dict[str, str]:
    """Normalize a comment structure to a consistent shape."""
    author_info = comment.get("author") or comment.get("user") or {}
    author = author_info.get("login") or "unknown"

    normalized = {
        "type": comment_type,
        "author": author,
        "createdAt": (
            comment.get("createdAt")
            or comment.get("submittedAt")
            or comment.get("created_at")
            or ""
        ),
        "url": comment.get("html_url") or comment.get("url") or "",
        "body": comment.get("body") or "",
        "state": comment.get("state") or "",
    }

    if comment.get("path"):
        normalized["path"] = str(comment.get("path") or "")
    if comment.get("line") is not None:
        normalized["line"] = str(comment.get("line"))
    if comment.get("side"):
        normalized["side"] = str(comment.get("side") or "")
    if comment.get("in_reply_to_id") is not None:
        normalized["inReplyToId"] = str(comment.get("in_reply_to_id"))

    return normalized


def should_include_review_entry(review: Dict[str, Any]) -> bool:
    """Decide whether a review object should appear in the comment stream."""
    review_body = review.get("body") or ""
    if review_body.strip():
        return True

    review_state = (review.get("state") or "").upper()
    return review_state in {"APPROVED", "CHANGES_REQUESTED"}


def get_pr_comments(pr_number: int) -> List[Dict[str, str]]:
    """Get issue comments, review summaries, inline review comments, and replies."""
    comments_json = run_command(f"gh pr view {pr_number} --json comments,reviews")
    data = json.loads(comments_json)

    normalized: List[Dict[str, str]] = []
    for comment in data.get("comments", []):
        normalized.append(normalize_comment_entry(comment, "issue"))

    for review in data.get("reviews", []):
        if should_include_review_entry(review):
            normalized.append(normalize_comment_entry(review, "review"))

    review_comments_json = run_command(
        f"gh api repos/{shlex.quote(get_repo_slug())}/pulls/{pr_number}/comments --paginate"
    )
    for review_comment in json.loads(review_comments_json):
        comment_type = (
            "review-reply"
            if review_comment.get("in_reply_to_id") is not None
            else "review-comment"
        )
        normalized.append(normalize_comment_entry(review_comment, comment_type))

    normalized.sort(key=lambda c: c.get("createdAt") or "")
    return normalized


def get_pr_checks(pr_number: int) -> List[Dict[str, str]]:
    """Get status check results for a specific PR."""
    checks_json = run_command(
        f"gh pr view {pr_number} --json statusCheckRollup"
    )
    data = json.loads(checks_json)

    checks: List[Dict[str, str]] = []
    for check in data.get("statusCheckRollup") or []:
        checks.append(
            {
                "name": check.get("name")
                or check.get("context")
                or check.get("title")
                or "unknown check",
                "status": check.get("status")
                or check.get("state")
                or "unknown",
                "conclusion": check.get("conclusion")
                or check.get("state")
                or "unknown",
                "detailsUrl": check.get("detailsUrl")
                or check.get("targetUrl")
                or "",
                "title": check.get("title") or "",
                "summary": check.get("summary") or check.get("text") or "",
            }
        )

    return checks


def extract_actions_run_id(details_url: str | None) -> str | None:
    """Extract the GitHub Actions run ID from a details URL."""
    if not details_url:
        return None
    match = re.search(r"/actions/runs/(\d+)", details_url)
    return match.group(1) if match else None


def get_failed_check_logs(check: Dict[str, str]) -> str | None:
    """Retrieve raw logs for failed GitHub Actions checks."""
    conclusion = (check.get("conclusion") or "").lower()
    if conclusion in {"success", "neutral", "skipped"}:
        return None

    run_id = extract_actions_run_id(check.get("detailsUrl") or "")
    if not run_id:
        return None

    try:
        print(
            f"Fetching logs for failed check '{check.get('name', 'unknown check')}' "
            f"(run {run_id})"
        )
        return run_command(f"gh run view {shlex.quote(run_id)} --log")
    except subprocess.CalledProcessError as exc:
        print(f"Warning: Failed to fetch logs for run {run_id}: {exc}")
        return None


def report_missing_files_on_checked_out_branch(files: List[str]) -> List[str]:
    """Report changed paths that are absent on the currently checked out branch."""
    missing_files: List[str] = []

    for file_path in files:
        if not os.path.exists(file_path):
            missing_files.append(file_path)

    if missing_files:
        print(
            "Including "
            f"{len(missing_files)} path(s) that are absent on the checked-out branch: "
            f"{', '.join(missing_files)}"
        )

    return missing_files


def filter_excluded_files(files: List[str]) -> Tuple[List[str], List[str]]:
    """Filter files that should be excluded from documents."""
    excluded_files: List[str] = []
    included_files: List[str] = []

    for file_path in files:
        if Path(file_path).name == "package-lock.json":
            excluded_files.append(file_path)
        else:
            included_files.append(file_path)

    if excluded_files:
        print(f"Skipping {len(excluded_files)} excluded file(s): {', '.join(excluded_files)}")

    return included_files, excluded_files


def checkout_pr_branch(pr_info: Dict[str, str], remote: str) -> str:
    """Checkout the requested PR by PR ref, not by an existing local branch name."""
    branch_name = pr_info["branch"]
    pr_number = pr_info["number"]
    fallback_branch = f"pr-{pr_number}"
    print(
        f"Resolving PR #{pr_number} into local branch {fallback_branch} "
        f"(head ref: {branch_name})..."
    )

    try:
        run_command(f"git fetch {shlex.quote(remote)} pull/{pr_number}/head")
        run_command(
            f"git checkout -B {shlex.quote(fallback_branch)} FETCH_HEAD"
        )
        print(f"✓ Checked out PR ref as {fallback_branch}")
        return fallback_branch
    except subprocess.CalledProcessError:
        print(
            f"PR ref for PR #{pr_number} was unavailable, "
            f"falling back to remote branch {branch_name}..."
        )

    remote_branch = f"{remote}/{branch_name}"
    try:
        run_command(f"git fetch {shlex.quote(remote)} {shlex.quote(branch_name)}")
        run_command(
            f"git checkout -B {shlex.quote(fallback_branch)} "
            f"{shlex.quote(remote_branch)}"
        )
        print(f"✓ Checked out remote branch as {fallback_branch}")
        return fallback_branch
    except subprocess.CalledProcessError as exc:
        print(f"Error: Could not checkout branch for PR #{pr_number}")
        raise exc


def generate_file_descriptions(files: List[str]) -> List[str]:
    """Generate descriptive names for files in the big_picture compilation."""
    file_args: List[str] = []

    for file_path in files:
        path = Path(file_path)
        desc = path.name

        if "backend" in path.parts:
            if path.name == "app.py":
                desc = "FastAPI app with endpoints and middleware"
            elif path.name == "auth.py":
                desc = "Authentication module"
            elif path.name == "test_api.py":
                desc = "API tests"
            elif path.name == "users.json":
                desc = "User credentials JSON"
            elif path.name == "requirements.txt":
                desc = "Backend requirements"
            else:
                desc = f"Backend {path.name}"
        elif "frontend" in path.parts:
            if "components" in path.parts:
                desc = f"{path.stem} component"
            elif path.name == "App.jsx":
                desc = "React main app component"
            elif path.name == "main.jsx":
                desc = "Frontend entry point"
            elif "auth" in path.parts:
                desc = f"Auth {path.stem} component"
            else:
                desc = f"Frontend {path.name}"

        file_args.append(f"{file_path}:{desc}")

    return file_args


def run_big_picture(
    pr_info: Dict[str, str],
    files: List[str],
    excluded_files: List[str],
    all_files: List[str],
    comments: List[Dict[str, str]],
    checks: List[Dict[str, str]],
    output_file: str,
    include_logs: bool = False,
    base_branch: str = "main",
    local_branch: str | None = None,
) -> bool:
    """Generate a git diff for the PR instead of full files."""
    branch_for_diff = local_branch or pr_info["branch"]
    print(f"Creating diff compilation for PR #{pr_info['number']}...")

    files_arg = " ".join(shlex.quote(f) for f in files)
    if files_arg:
        cmd = f"git diff {shlex.quote(base_branch)}...{shlex.quote(branch_for_diff)} -- {files_arg}"
        diff_output = run_command(cmd)
    else:
        diff_output = ""

    summary_text = " ".join(pr_info.get("body", "").split()) or "(no summary provided)"

    with open(output_file, "w", encoding="utf-8") as diff_file:
        diff_file.write(f"# PR #{pr_info['number']}: {pr_info['title']}\n")
        diff_file.write(f"# PR Number: {pr_info['number']}\n")
        diff_file.write(f"# Branch: {branch_for_diff}\n")
        diff_file.write(f"# Base: {base_branch}\n")
        diff_file.write(f"# Author: {pr_info.get('author', 'unknown')}\n")
        diff_file.write(f"# Created: {pr_info.get('createdAt', '')}\n")
        diff_file.write(f"# URL: {pr_info.get('url', '')}\n")
        diff_file.write(f"# Summary: {summary_text}\n")
        diff_file.write(f"# Changed files (total): {len(all_files)}\n")
        diff_file.write(f"# Included files: {len(files)}\n")
        diff_file.write(f"# Excluded files: {len(excluded_files)}\n")
        diff_file.write(f"# All files: {', '.join(all_files) if all_files else '(none)'}\n")
        diff_file.write(
            f"# Included file list: {', '.join(files) if files else '(none)'}\n"
        )
        diff_file.write(
            f"# Excluded file list: {', '.join(excluded_files) if excluded_files else '(none)'}\n\n"
        )
        diff_file.write("=" * 80 + "\n")
        if files:
            diff_file.write(diff_output if diff_output else "# No differences found\n")
        else:
            diff_file.write(
                "# No included files for diff generation.\n"
                "# All changed files for this PR were excluded from diff output.\n"
            )
        diff_file.write("\n\n")
        diff_file.write("=" * 80 + "\n")
        diff_file.write(f"Checks ({len(checks)}):\n")

        if not checks:
            diff_file.write("# No checks found\n")
        else:
            for check in checks:
                name = check.get("name") or "unknown check"
                status = check.get("status") or "unknown"
                conclusion = check.get("conclusion") or "unknown"
                details_url = check.get("detailsUrl") or ""
                log_output = check.get("logOutput") or ""
                heading = f"- {name}: status={status}, conclusion={conclusion}"
                if details_url:
                    heading += f" [{details_url}]"
                diff_file.write(heading + "\n")

                summary_text = check.get("summary") or check.get("title") or ""
                if summary_text:
                    for line in summary_text.splitlines():
                        diff_file.write(f"    {line}\n")
                if include_logs and log_output:
                    diff_file.write("    Logs:\n")
                    for line in log_output.splitlines():
                        diff_file.write(f"    {line}\n")

        diff_file.write("\n")
        diff_file.write("=" * 80 + "\n")
        diff_file.write(f"Comments ({len(comments)}):\n")

        if not comments:
            diff_file.write("# No comments found\n")
        else:
            for comment in comments:
                timestamp = comment.get("createdAt") or "unknown time"
                author = comment.get("author") or "unknown author"
                comment_type = comment.get("type") or "comment"
                url = comment.get("url") or ""
                state = comment.get("state") or ""
                heading = f"- [{timestamp}] {author} ({comment_type}"
                if state:
                    heading += f", state={state}"
                heading += ")"
                if comment.get("path"):
                    heading += f" on {comment['path']}"
                    if comment.get("line"):
                        heading += f":{comment['line']}"
                if comment.get("inReplyToId"):
                    heading += f" reply-to={comment['inReplyToId']}"
                if url:
                    heading += f" [{url}]"
                diff_file.write(heading + "\n")
                body = comment.get("body") or ""
                lines = body.splitlines() or ["(no content)"]
                for line in lines:
                    diff_file.write(f"    {line}\n")
                diff_file.write("\n")

    print(f"✓ Created diff: {output_file}")
    return True


def create_master_comparison(
    pr_files: List[Tuple[Dict[str, str], str]],
    selection_requested: str,
    selection_canonical: str,
    selected_prs: List[int],
    output_file: str,
    include_logs: bool = False,
) -> bool:
    """Create a master comparison file combining all individual PR diff files."""
    print("Creating master comparison file...")

    if not pr_files:
        print("Warning: No individual PR files found for master comparison")
        return False

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# Master Comparison{log_note}\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_prs
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total PRs: {len(pr_files)}\n")
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for idx, (pr_info, pr_file) in enumerate(pr_files, 1):
            outf.write("\n" + "=" * 80 + "\n")
            outf.write(f"# PR {idx}/{len(pr_files)} - #{pr_info['number']}: {pr_info['title']}\n")
            outf.write("=" * 80 + "\n\n")

            with open(pr_file, "r", encoding="utf-8") as inf:
                outf.write(inf.read())

            outf.write("\n\n")

    print(f"✓ Created master comparison: {output_file}")
    return True


def create_touched_files_compilation(
    touched_files: Set[str],
    touched_file_prs: Dict[str, Set[int]],
    base_branch: str,
    selection_requested: str,
    selection_canonical: str,
    selected_prs: List[int],
    output_file: str,
    master_comparison_file: str | None = None,
    include_logs: bool = False,
) -> bool:
    """Create a compilation of unique touched files from the base branch."""
    print("Creating touched files compilation...")

    if not touched_files:
        print("Warning: No touched files available for compilation")
        return False

    sorted_files = sorted(touched_files)

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# Touched Files{log_note} (base branch)\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_prs
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total unique files: {len(sorted_files)}\n")
        outf.write(f"# Source branch: {base_branch}\n")
        outf.write(
            "# Includes all changed paths from the selected PRs, including deleted "
            "or otherwise excluded diff paths when they exist on the base branch.\n"
        )
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for file_path in sorted_files:
            ref_path = f"{base_branch}:{file_path}"
            try:
                file_contents = run_command(f"git show {shlex.quote(ref_path)}")
            except subprocess.CalledProcessError:
                print(
                    f"Skipping {file_path} because it does not exist on {base_branch}"
                )
                continue

            outf.write("=" * 80 + "\n")
            outf.write(f"# File: {file_path}\n")
            outf.write(f"# Source: {base_branch}\n")
            file_prs = sorted(touched_file_prs.get(file_path, set()))
            if file_prs:
                outf.write(f"# Touched by PRs: {', '.join(str(pr) for pr in file_prs)}\n")
            else:
                outf.write("# Touched by PRs: (unknown)\n")
            outf.write("\n")
            outf.write(file_contents)
            if not file_contents.endswith("\n"):
                outf.write("\n")
            outf.write("\n\n")

        if master_comparison_file and os.path.exists(master_comparison_file):
            outf.write("=" * 80 + "\n")
            outf.write(
                "# Appended master comparison (diffs and summaries)\n\n"
            )
            with open(master_comparison_file, "r", encoding="utf-8") as master_file:
                outf.write(master_file.read())

    print(f"✓ Created touched files compilation: {output_file}")
    return True


def create_summary_compilation(
    pr_files: List[Tuple[Dict[str, str], str]],
    selection_requested: str,
    selection_canonical: str,
    selected_prs: List[int],
    output_file: str,
    include_logs: bool = False,
) -> bool:
    """Create a concise summary document for all processed PRs."""
    print("Creating summary compilation file...")

    if not pr_files:
        print("Warning: No PRs available to summarize")
        return False

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# PR Summary Compilation{log_note}\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_prs
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total PRs: {len(pr_files)}\n")
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for idx, (pr_info, pr_file) in enumerate(pr_files, 1):
            summary_text = " ".join(pr_info.get("body", "").split()) or "(no summary provided)"

            outf.write(f"## PR {idx}/{len(pr_files)} - #{pr_info['number']}: {pr_info['title']}\n")
            outf.write(f"- Author: {pr_info.get('author', 'unknown')}\n")
            outf.write(f"- Created: {pr_info.get('createdAt', '')}\n")
            outf.write(f"- URL: {pr_info.get('url', '')}\n")
            outf.write(f"- Summary: {summary_text}\n")
            outf.write(f"- Detailed file: {pr_file}\n")
            outf.write("\n")

    print(f"✓ Created summary compilation: {output_file}")
    return True


def create_round_robin_comparisons(
    processed_prs: List[Dict[str, object]],
    output_dir: str,
    selection_requested: str,
    selection_canonical: str,
    selected_prs: List[int],
) -> List[str]:
    """Create pairwise comparison files for every PR combination."""
    print("Creating round-robin comparisons...")

    if len(processed_prs) < 2:
        print("Warning: Not enough PRs for round-robin comparisons")
        return []

    output_files: List[str] = []

    for left, right in combinations(processed_prs, 2):
        left_info = left["info"]
        right_info = right["info"]
        left_branch = left["local_branch"]
        right_branch = right["local_branch"]
        left_files = left["files"]
        right_files = right["files"]

        if not isinstance(left_info, dict) or not isinstance(right_info, dict):
            continue
        if not isinstance(left_branch, str) or not isinstance(right_branch, str):
            continue
        if not isinstance(left_files, list) or not isinstance(right_files, list):
            continue

        left_number = left_info.get("number")
        right_number = right_info.get("number")
        if left_number is None or right_number is None:
            continue

        output_file = os.path.join(
            output_dir, f"pr-{left_number}-versus-{right_number}.txt"
        )

        combined_files = sorted(set(left_files) | set(right_files))
        if not combined_files:
            print(
                f"Skipping round-robin comparison for PR #{left_number} vs PR #{right_number} "
                "because there are no included files to compare"
            )
            continue

        files_arg = " ".join(shlex.quote(f) for f in combined_files)
        diff_cmd = (
            f"git diff {shlex.quote(left_branch)} {shlex.quote(right_branch)}"
        )
        diff_cmd += f" -- {files_arg}"

        diff_output = run_command(diff_cmd)

        left_summary = " ".join(left_info.get("body", "").split()) or "(no summary provided)"
        right_summary = " ".join(right_info.get("body", "").split()) or "(no summary provided)"

        with open(output_file, "w", encoding="utf-8") as outf:
            outf.write(
                f"# PR #{left_number} vs PR #{right_number}: "
                f"{left_info.get('title', '')} ↔ {right_info.get('title', '')}\n"
            )
            for line in selection_header_lines(
                selection_requested, selection_canonical, selected_prs
            ):
                outf.write(f"{line}\n")
            outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            outf.write(f"# Left branch: {left_branch}\n")
            outf.write(f"# Right branch: {right_branch}\n")
            outf.write(f"# Left author: {left_info.get('author', 'unknown')}\n")
            outf.write(f"# Right author: {right_info.get('author', 'unknown')}\n")
            outf.write(f"# Left URL: {left_info.get('url', '')}\n")
            outf.write(f"# Right URL: {right_info.get('url', '')}\n")
            outf.write(f"# Left summary: {left_summary}\n")
            outf.write(f"# Right summary: {right_summary}\n")
            outf.write(f"# Files compared: {len(combined_files)}\n")
            outf.write(f"# Files: {', '.join(combined_files)}\n\n")
            outf.write("=" * 80 + "\n")
            outf.write(diff_output if diff_output else "# No differences found\n")
            outf.write("\n\n")

        output_files.append(output_file)

    print(
        f"✓ Created {len(output_files)} round-robin comparison file(s) "
        f"for selection {selection_canonical}"
    )
    return output_files


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Automate diff generation for selected pull requests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "pr_selection",
        nargs="?",
        help=(
            "PR selection string like '123-130,135,140-142'. "
            "Accepts commas, ranges, whitespace, and optional # prefixes."
        ),
    )
    parser.add_argument(
        "--prs",
        dest="pr_selection",
        help=(
            "Alias for the PR selection string. "
            "Examples: '123-130,135,140-142' or '#123, #125-#127'."
        ),
    )
    parser.add_argument(
        "--base-branch",
        default="main",
        help="Base branch to diff against (default: main)",
    )
    parser.add_argument(
        "--remote",
        default="origin",
        help="Remote name to fetch PR branches from (default: origin)",
    )
    parser.add_argument(
        "--output-dir",
        default="/tmp",
        help="Directory where output files will be written (default: /tmp)",
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Don't return to the base branch at the end",
    )

    args = parser.parse_args()

    if not args.pr_selection:
        parser.error("pr_selection is required (e.g. '123-130,135,140-142').")

    try:
        selected_prs = parse_pr_selection(args.pr_selection)
    except SelectionParseError as exc:
        parser.error(str(exc))

    selection_requested = args.pr_selection
    selection_canonical = format_pr_selection(selected_prs)
    selection_tag = build_selection_tag(selected_prs, selection_canonical)
    os.makedirs(args.output_dir, exist_ok=True)

    print(f"Requested PR selection: {selection_requested}")
    print(f"Canonical PR selection: {selection_canonical}")
    if selected_prs:
        preview = format_pr_list_preview(selected_prs)
        print(
            f"Expanded PRs: count={len(selected_prs)} "
            f"min={min(selected_prs)} max={max(selected_prs)} preview={preview}"
        )

    check_current_branch(args.base_branch)

    try:
        fetch_remote_branches(args.remote)

        print(f"Collecting info for PR selection: {selection_canonical}...")
        pr_infos: List[Dict[str, str]] = []
        touched_files: Set[str] = set()
        touched_file_prs: Dict[str, Set[int]] = {}
        missing_prs: List[int] = []

        for pr_num in selected_prs:
            try:
                pr_info = get_pr_info(pr_num)
                pr_infos.append(pr_info)
                print(f"  PR #{pr_num}: {pr_info['title']}")
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
                print(f"  PR #{pr_num}: Not found or inaccessible ({exc})")
                missing_prs.append(pr_num)

        if not pr_infos:
            print("Error: No valid PRs found for the requested selection")
            sys.exit(1)

        successful_prs: List[Tuple[Dict[str, str], str]] = []
        successful_prs_with_logs: List[Tuple[Dict[str, str], str]] = []
        processed_prs: List[Dict[str, object]] = []
        processed_prs_with_logs: List[Dict[str, object]] = []

        for pr_info in pr_infos:
            print(f"\n--- Processing PR #{pr_info['number']}: {pr_info['title']} ---")

            try:
                all_files = get_pr_changed_files(pr_info["number"])
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
                print(f"Failed to retrieve files for PR #{pr_info['number']}: {exc}")
                continue

            if not all_files:
                print(f"No changed files found for PR #{pr_info['number']}")
                continue

            print(f"Total changed files: {len(all_files)}")

            included_files, _excluded_files = filter_excluded_files(all_files)

            try:
                local_branch = checkout_pr_branch(pr_info, args.remote)
            except subprocess.CalledProcessError:
                print(f"Failed to checkout branch for PR #{pr_info['number']}")
                continue

            if included_files:
                report_missing_files_on_checked_out_branch(included_files)

            if included_files:
                print(
                    f"Files to process ({len(included_files)}): "
                    f"{', '.join(included_files)}"
                )
            else:
                print(
                    f"All changed files for PR #{pr_info['number']} were excluded "
                    f"from diff output; preserving PR metadata/comments/checks."
                )
            touched_files.update(all_files)
            for file_path in all_files:
                touched_file_prs.setdefault(file_path, set()).add(pr_info["number"])

            try:
                comments = get_pr_comments(pr_info["number"])
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
                print(f"Failed to retrieve comments for PR #{pr_info['number']}: {exc}")
                comments = []

            try:
                checks_with_logs: List[Dict[str, str]] = []
                checks = get_pr_checks(pr_info["number"])
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
                print(f"Failed to retrieve checks for PR #{pr_info['number']}: {exc}")
                checks = []
                checks_with_logs = []
            else:
                for check in checks:
                    check_copy = dict(check)
                    logs = get_failed_check_logs(check_copy)
                    if logs:
                        check_copy["logOutput"] = logs
                    checks_with_logs.append(check_copy)

            output_file = os.path.join(
                args.output_dir, f"pr-{pr_info['number']}-implementation.txt"
            )
            output_file_with_logs = os.path.join(
                args.output_dir, f"pr-{pr_info['number']}-implementation-with-logs.txt"
            )
            if run_big_picture(
                pr_info,
                included_files,
                _excluded_files,
                all_files,
                comments,
                checks,
                output_file,
                include_logs=False,
                base_branch=args.base_branch,
                local_branch=local_branch,
            ):
                successful_prs.append((pr_info, output_file))
                processed_prs.append(
                    {
                        "info": pr_info,
                        "file": output_file,
                        "local_branch": local_branch,
                        "files": included_files,
                    }
                )
            if run_big_picture(
                pr_info,
                included_files,
                _excluded_files,
                all_files,
                comments,
                checks_with_logs,
                output_file_with_logs,
                include_logs=True,
                base_branch=args.base_branch,
                local_branch=local_branch,
            ):
                successful_prs_with_logs.append((pr_info, output_file_with_logs))
                processed_prs_with_logs.append(
                    {
                        "info": pr_info,
                        "file": output_file_with_logs,
                        "local_branch": local_branch,
                        "files": included_files,
                    }
                )

        if successful_prs:
            requested_count = len(selected_prs)
            processed_numbers = {info["number"] for info, _ in successful_prs}
            processed_count = len(processed_numbers)
            skipped_prs = [pr for pr in selected_prs if pr not in processed_numbers]
            print(
                f"\nRequested PR count: {requested_count}; "
                f"processed PR count: {processed_count}"
            )
            if missing_prs:
                print(f"Missing/inaccessible PRs: {', '.join(map(str, missing_prs))}")
            if skipped_prs:
                print(f"Skipped PRs after processing: {', '.join(map(str, skipped_prs))}")

            master_output = os.path.join(
                args.output_dir, f"pr-comparison-{selection_tag}.txt"
            )
            create_master_comparison(
                successful_prs,
                selection_requested,
                selection_canonical,
                selected_prs,
                master_output,
            )

            summary_output = os.path.join(
                args.output_dir, f"pr-summaries-{selection_tag}.txt"
            )
            create_summary_compilation(
                successful_prs,
                selection_requested,
                selection_canonical,
                selected_prs,
                summary_output,
            )

            touched_output = os.path.join(
                args.output_dir, f"pr-touched-files-{selection_tag}.txt"
            )
            create_touched_files_compilation(
                touched_files,
                touched_file_prs,
                args.base_branch,
                selection_requested,
                selection_canonical,
                selected_prs,
                touched_output,
                master_output,
            )
            round_robin_outputs = create_round_robin_comparisons(
                processed_prs,
                args.output_dir,
                selection_requested,
                selection_canonical,
                selected_prs,
            )

            print(f"\n✓ Successfully processed {len(successful_prs)} PR(s) (without logs)")
            print(f"✓ Individual files: {args.output_dir}/pr-{{num}}-implementation.txt")
            print(f"✓ Master comparison: {master_output}")
            print(f"✓ Summary compilation: {summary_output}")
            print(f"✓ Touched files compilation: {touched_output}")
            if round_robin_outputs:
                print(
                    "✓ Round-robin comparisons: "
                    f"{args.output_dir}/pr-{{left}}-versus-{{right}}.txt"
                )
        else:
            print("\nNo PRs were successfully processed (without logs)")

        if successful_prs_with_logs:
            master_output_with_logs = os.path.join(
                args.output_dir, f"pr-comparison-{selection_tag}-with-logs.txt"
            )
            create_master_comparison(
                successful_prs_with_logs,
                selection_requested,
                selection_canonical,
                selected_prs,
                master_output_with_logs,
                include_logs=True,
            )

            summary_output_with_logs = os.path.join(
                args.output_dir, f"pr-summaries-{selection_tag}-with-logs.txt"
            )
            create_summary_compilation(
                successful_prs_with_logs,
                selection_requested,
                selection_canonical,
                selected_prs,
                summary_output_with_logs,
                include_logs=True,
            )

            touched_output_with_logs = os.path.join(
                args.output_dir, f"pr-touched-files-{selection_tag}-with-logs.txt"
            )
            create_touched_files_compilation(
                touched_files,
                touched_file_prs,
                args.base_branch,
                selection_requested,
                selection_canonical,
                selected_prs,
                touched_output_with_logs,
                master_output_with_logs,
                include_logs=True,
            )

            print(f"\n✓ Successfully processed {len(successful_prs_with_logs)} PR(s) (with logs)")
            print(f"✓ Individual files (with logs): {args.output_dir}/pr-{{num}}-implementation-with-logs.txt")
            print(f"✓ Master comparison (with logs): {master_output_with_logs}")
            print(f"✓ Summary compilation (with logs): {summary_output_with_logs}")
            print(f"✓ Touched files compilation (with logs): {touched_output_with_logs}")
        else:
            print("\nNo PRs were successfully processed (with logs)")

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        if not args.no_cleanup:
            try:
                checkout_base_branch(args.base_branch)
                print(f"✓ Returned to {args.base_branch} branch")
            except subprocess.CalledProcessError:
                print(f"Warning: Failed to return to {args.base_branch} branch")


if __name__ == "__main__":
    main()
