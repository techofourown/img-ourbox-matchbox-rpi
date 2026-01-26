#!/usr/bin/env python3
"""
commit_batch_big_picture - Automate diff generation for ranges of commits

This tool automates the process of creating git diffs and metadata summaries
for selected commits, including check results and touched file snapshots.
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
from itertools import combinations
from pathlib import Path
from typing import Dict, List, Set, Tuple


class SelectionParseError(ValueError):
    """Raised when a commit selection string cannot be parsed."""


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


def run_command_result(cmd: str) -> subprocess.CompletedProcess:
    """Run a shell command and return the CompletedProcess."""
    return subprocess.run(
        cmd,
        shell=True,
        check=False,
        capture_output=True,
        text=True,
    )


def run_command_bytes(cmd: str, check: bool = True) -> bytes:
    """Run a shell command and return raw stdout bytes."""
    result = subprocess.run(
        cmd,
        shell=True,
        check=check,
        capture_output=True,
        text=False,
    )
    return result.stdout or b""


def decode_file_snapshot(content: bytes) -> Tuple[str, bool]:
    """Decode git show output while flagging probable binary content."""
    if not content:
        return "", False
    if b"\0" in content:
        return "# (binary file omitted from report)", True

    control_bytes = sum(
        1 for byte in content if byte < 9 or (13 < byte < 32)
    )
    if control_bytes / len(content) > 0.1:
        return "# (binary file omitted from report)", True

    return content.decode("utf-8", errors="replace"), False


def resolve_commit(ref: str) -> str:
    """Resolve a commit ref to a full SHA."""
    cleaned = ref.strip()
    if not cleaned:
        raise SelectionParseError("Invalid commit token: empty ref")
    try:
        sha = run_command(f"git rev-parse --verify {shlex.quote(cleaned)}")
    except subprocess.CalledProcessError as exc:
        raise SelectionParseError(
            f"Invalid commit token '{ref}': {exc}"
        ) from exc
    if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise SelectionParseError(
            f"Invalid commit token '{ref}': resolved to '{sha}'"
        )
    return sha


def ensure_ancestor(start: str, end: str, original: str) -> None:
    """Ensure start is an ancestor of end."""
    result = run_command_result(
        f"git merge-base --is-ancestor {shlex.quote(start)} {shlex.quote(end)}"
    )
    if result.returncode != 0:
        raise SelectionParseError(
            f"Invalid commit range '{original}': '{start}' is not an ancestor of '{end}'."
        )


def parse_commit_selection(selection: str) -> List[str]:
    """Parse a selection string into an ordered list of unique commit SHAs."""
    original = selection
    trimmed = selection.strip()
    if not trimmed:
        raise SelectionParseError(
            "Invalid commit selection: empty input. "
            "Expected format like 'abc123,def456' or 'abc123-def456'."
        )

    segments = [segment.strip() for segment in trimmed.split(",")]
    if any(segment == "" for segment in segments):
        raise SelectionParseError(
            f"Invalid commit selection segment '' in '{original}'. "
            "Expected format like 'abc123,def456' or 'abc123-def456'."
        )

    selected: List[str] = []
    seen: Set[str] = set()

    for segment in segments:
        cleaned = re.sub(r"\s+", "", segment)
        if not cleaned:
            raise SelectionParseError(
                f"Invalid commit selection segment '{segment}' in '{original}'. "
                "Expected format like 'abc123,def456' or 'abc123-def456'."
            )

        parts = cleaned.split("-")
        if len(parts) == 1:
            commit = resolve_commit(parts[0])
            if commit not in seen:
                selected.append(commit)
                seen.add(commit)
        elif len(parts) == 2:
            start_ref, end_ref = parts
            if not start_ref or not end_ref:
                raise SelectionParseError(
                    f"Invalid commit range '{segment}' in '{original}'. "
                    "Expected format like 'abc123-def456'."
                )
            start = resolve_commit(start_ref)
            end = resolve_commit(end_ref)
            ensure_ancestor(start, end, segment)
            if start == end:
                if start not in seen:
                    selected.append(start)
                    seen.add(start)
                continue
            range_commits = run_command(
                f"git rev-list --reverse {shlex.quote(start)}..{shlex.quote(end)}"
            ).splitlines()
            for commit in [start] + range_commits:
                if commit and commit not in seen:
                    selected.append(commit)
                    seen.add(commit)
        else:
            raise SelectionParseError(
                f"Invalid commit selection segment '{segment}' in '{original}'. "
                "Expected format like 'abc123,def456' or 'abc123-def456'."
            )

    if not selected:
        raise SelectionParseError(
            f"Invalid commit selection '{original}': no commits parsed. "
            "Expected format like 'abc123,def456' or 'abc123-def456'."
        )

    return selected


def format_commit_selection(commits: List[str]) -> str:
    """Format a list of commit SHAs into a canonical selection string."""
    return ",".join(commits)


def build_selection_tag(selected_commits: List[str], selection_canonical: str) -> str:
    selection_hash = hashlib.sha1(selection_canonical.encode("utf-8")).hexdigest()[:8]
    if not selected_commits:
        return f"0commits-{selection_hash}"
    first_short = selected_commits[0][:8]
    last_short = selected_commits[-1][:8]
    return f"{first_short}-{last_short}-{len(selected_commits)}commits-{selection_hash}"


def format_commit_list_preview(commits: List[str], max_items: int = 10, edge_items: int = 3) -> str:
    if len(commits) <= max_items:
        return ", ".join(commit[:8] for commit in commits)
    head = ", ".join(commit[:8] for commit in commits[:edge_items])
    tail = ", ".join(commit[:8] for commit in commits[-edge_items:])
    return f"{head} ... {tail}"


def selection_header_lines(
    selection_requested: str, selection_canonical: str, selected_commits: List[str]
) -> List[str]:
    lines = [
        f"# Commit selection (requested): {selection_requested}",
        f"# Commit selection (canonical): {selection_canonical}",
    ]
    if selected_commits:
        if len(selected_commits) <= 20:
            expanded = ", ".join(commit[:8] for commit in selected_commits)
            lines.append(f"# Expanded commits (count={len(selected_commits)}): {expanded}")
        else:
            preview = format_commit_list_preview(selected_commits)
            lines.append(
                f"# Expanded commits: count={len(selected_commits)} "
                f"min={selected_commits[0][:8]} max={selected_commits[-1][:8]} preview={preview}"
            )
    else:
        lines.append("# Expanded commits: count=0")
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


def get_repo_url() -> str:
    """Get the repository URL via gh, if available."""
    try:
        return run_command("gh repo view --json url -q .url")
    except subprocess.CalledProcessError:
        return ""


def get_repo_name_with_owner() -> str:
    """Get repository name with owner via gh."""
    return run_command("gh repo view --json nameWithOwner -q .nameWithOwner")


def get_commit_info(commit_sha: str, repo_url: str) -> Dict[str, str]:
    """Get metadata for a specific commit."""
    output = run_command(
        "git show -s --format=%H%x00%h%x00%an%x00%ae%x00%ad%x00%s%x00%b "
        f"--date=iso-strict {shlex.quote(commit_sha)}"
    )
    parts = output.split("\x00")
    if len(parts) < 7:
        raise ValueError(f"Unexpected git show output for commit {commit_sha}")
    full_sha, short_sha, author, email, date, subject, body = parts[:7]
    return {
        "sha": full_sha,
        "short": short_sha,
        "author": author,
        "email": email,
        "date": date,
        "subject": subject,
        "body": body.strip(),
        "url": f"{repo_url}/commit/{full_sha}" if repo_url else "",
    }


def get_commit_parents(commit_sha: str) -> List[str]:
    """Return parent SHAs for the given commit."""
    output = run_command(
        f"git rev-list --parents -n 1 {shlex.quote(commit_sha)}"
    )
    parts = output.split()
    return parts[1:] if len(parts) > 1 else []


def get_commit_changed_files(commit_sha: str) -> List[str]:
    """Get list of changed files for a specific commit."""
    parents = get_commit_parents(commit_sha)
    merge_flag = "-m " if len(parents) > 1 else ""
    output = run_command(
        f"git diff-tree {merge_flag}--no-commit-id --name-only -r --root {shlex.quote(commit_sha)}"
    )
    files = [line for line in output.splitlines() if line.strip()]
    return list(dict.fromkeys(files))


def normalize_check_entry(check: Dict[str, str], check_type: str) -> Dict[str, str]:
    return {
        "type": check_type,
        "name": check.get("name") or "unknown check",
        "status": check.get("status") or check.get("state") or "unknown",
        "conclusion": check.get("conclusion") or check.get("state") or "unknown",
        "detailsUrl": check.get("detailsUrl") or check.get("details_url") or "",
        "title": check.get("title") or "",
        "summary": check.get("summary") or check.get("text") or "",
    }


def get_commit_checks(commit_sha: str, repo: str) -> List[Dict[str, str]]:
    """Get status check results for a specific commit."""
    checks: List[Dict[str, str]] = []

    check_runs_json = run_command(
        f"gh api repos/{shlex.quote(repo)}/commits/{shlex.quote(commit_sha)}/check-runs"
    )
    check_runs = json.loads(check_runs_json)
    for check in check_runs.get("check_runs", []) or []:
        checks.append(normalize_check_entry(check, "check-run"))

    status_json = run_command(
        f"gh api repos/{shlex.quote(repo)}/commits/{shlex.quote(commit_sha)}/status"
    )
    status_data = json.loads(status_json)
    for status in status_data.get("statuses", []) or []:
        checks.append(normalize_check_entry(status, "status"))

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


def checks_all_green(checks: List[Dict[str, str]]) -> bool:
    """Determine whether all checks conclude successfully."""
    if not checks:
        return False
    for check in checks:
        conclusion = (check.get("conclusion") or check.get("status") or "").lower()
        if conclusion not in {"success", "neutral", "skipped"}:
            return False
    return True


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


def run_commit_big_picture(
    commit_info: Dict[str, str],
    files: List[str],
    checks: List[Dict[str, str]],
    output_file: str,
    include_logs: bool = False,
) -> bool:
    """Generate a git diff compilation for a commit."""
    commit_sha = commit_info["sha"]
    print(f"Creating diff compilation for commit {commit_info['short']}...")

    if not files:
        print(f"Warning: No files found for commit {commit_info['short']}")
        return False

    files_arg = " ".join(shlex.quote(f) for f in files)
    diff_output = run_command(
        f"git show --pretty=format: {shlex.quote(commit_sha)} -- {files_arg}"
    )

    body_text = " ".join(commit_info.get("body", "").split()) or "(no body provided)"
    summary_text = " ".join(commit_info.get("subject", "").split()) or "(no subject)"
    checks_green = checks_all_green(checks)

    with open(output_file, "w", encoding="utf-8") as diff_file:
        diff_file.write(f"# Commit {commit_info['short']}: {summary_text}\n")
        diff_file.write(f"# SHA: {commit_sha}\n")
        diff_file.write(f"# Author: {commit_info.get('author', 'unknown')} <{commit_info.get('email', '')}>\n")
        diff_file.write(f"# Date: {commit_info.get('date', '')}\n")
        diff_file.write(f"# URL: {commit_info.get('url', '')}\n")
        diff_file.write(f"# Body: {body_text}\n")
        diff_file.write(f"# Checks green: {checks_green}\n")
        diff_file.write(f"# Changed files: {len(files)}\n")
        diff_file.write(f"# Files: {', '.join(files)}\n\n")
        diff_file.write("=" * 80 + "\n")
        diff_file.write(diff_output if diff_output else "# No differences found\n")
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

                summary = check.get("summary") or check.get("title") or ""
                if summary:
                    for line in summary.splitlines():
                        diff_file.write(f"    {line}\n")
                if include_logs and log_output:
                    diff_file.write("    Logs:\n")
                    for line in log_output.splitlines():
                        diff_file.write(f"    {line}\n")

        diff_file.write("\n")

    print(f"✓ Created diff: {output_file}")
    return True


def create_master_comparison(
    commit_files: List[Tuple[Dict[str, str], str]],
    selection_requested: str,
    selection_canonical: str,
    selected_commits: List[str],
    output_file: str,
    include_logs: bool = False,
) -> bool:
    """Create a master comparison file combining all individual commit diff files."""
    print("Creating master comparison file...")

    if not commit_files:
        print("Warning: No individual commit files found for master comparison")
        return False

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# Master Comparison{log_note}\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_commits
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total commits: {len(commit_files)}\n")
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for idx, (commit_info, commit_file) in enumerate(commit_files, 1):
            outf.write("\n" + "=" * 80 + "\n")
            outf.write(
                f"# Commit {idx}/{len(commit_files)} - {commit_info['short']}: "
                f"{commit_info.get('subject', '')}\n"
            )
            outf.write("=" * 80 + "\n\n")

            with open(commit_file, "r", encoding="utf-8") as inf:
                outf.write(inf.read())

            outf.write("\n\n")

    print(f"✓ Created master comparison: {output_file}")
    return True


def get_commit_parent(commit_sha: str) -> str | None:
    output = run_command(
        f"git rev-list --parents -n 1 {shlex.quote(commit_sha)}"
    )
    parts = output.split()
    if len(parts) <= 1:
        return None
    return parts[1]


def create_touched_files_compilation(
    commits: List[Dict[str, str]],
    selection_requested: str,
    selection_canonical: str,
    selected_commits: List[str],
    output_file: str,
    master_comparison_file: str | None = None,
    include_logs: bool = False,
) -> bool:
    """Create a compilation of touched files with before/after snapshots."""
    print("Creating touched files compilation...")

    if not commits:
        print("Warning: No commits available for compilation")
        return False

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# Touched Files{log_note} (commit snapshots)\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_commits
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total commits: {len(commits)}\n")
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for commit_info in commits:
            commit_sha = commit_info["sha"]
            commit_short = commit_info["short"]
            subject = commit_info.get("subject", "")
            parent = get_commit_parent(commit_sha)
            files = get_commit_changed_files(commit_sha)
            files, _excluded = filter_excluded_files(files)
            if not files:
                continue

            outf.write("=" * 80 + "\n")
            outf.write(f"# Commit {commit_short}: {subject}\n")
            outf.write(f"# SHA: {commit_sha}\n")
            outf.write(f"# Parent: {parent or '(none)'}\n")
            outf.write(f"# Files: {', '.join(files)}\n")
            outf.write("=" * 80 + "\n\n")

            for file_path in files:
                outf.write("-" * 80 + "\n")
                outf.write(f"# File: {file_path}\n")
                outf.write(f"# Commit: {commit_short}\n\n")

                before_binary = False
                if parent:
                    try:
                        before_raw = run_command_bytes(
                            f"git show {shlex.quote(parent)}:{shlex.quote(file_path)}"
                        )
                        before_contents, before_binary = decode_file_snapshot(before_raw)
                    except subprocess.CalledProcessError:
                        before_contents = "# (file did not exist before commit)"
                else:
                    before_contents = "# (no parent commit)"

                after_binary = False
                try:
                    after_raw = run_command_bytes(
                        f"git show {shlex.quote(commit_sha)}:{shlex.quote(file_path)}"
                    )
                    after_contents, after_binary = decode_file_snapshot(after_raw)
                except subprocess.CalledProcessError:
                    after_contents = "# (file removed in commit)"

                if before_binary or after_binary:
                    print(
                        f"Skipping binary file contents for {file_path} in commit {commit_short}"
                    )

                diff_output = run_command(
                    f"git show --pretty=format: {shlex.quote(commit_sha)} -- {shlex.quote(file_path)}"
                )

                outf.write("# Before\n")
                outf.write(before_contents)
                if not before_contents.endswith("\n"):
                    outf.write("\n")
                outf.write("\n# After\n")
                outf.write(after_contents)
                if not after_contents.endswith("\n"):
                    outf.write("\n")
                outf.write("\n# Diff\n")
                outf.write(diff_output if diff_output else "# No differences found\n")
                outf.write("\n\n")

        if master_comparison_file and os.path.exists(master_comparison_file):
            outf.write("=" * 80 + "\n")
            outf.write("# Appended master comparison (diffs and summaries)\n\n")
            with open(master_comparison_file, "r", encoding="utf-8") as master_file:
                outf.write(master_file.read())

    print(f"✓ Created touched files compilation: {output_file}")
    return True


def create_summary_compilation(
    commit_files: List[Tuple[Dict[str, str], str]],
    selection_requested: str,
    selection_canonical: str,
    selected_commits: List[str],
    output_file: str,
    include_logs: bool = False,
) -> bool:
    """Create a concise summary document for all processed commits."""
    print("Creating summary compilation file...")

    if not commit_files:
        print("Warning: No commits available to summarize")
        return False

    with open(output_file, "w", encoding="utf-8") as outf:
        log_note = " (with logs)" if include_logs else ""
        outf.write(f"# Commit Summary Compilation{log_note}\n")
        for line in selection_header_lines(
            selection_requested, selection_canonical, selected_commits
        ):
            outf.write(f"{line}\n")
        outf.write(f"# Total commits: {len(commit_files)}\n")
        outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        outf.write("=" * 80 + "\n\n")

        for idx, (commit_info, commit_file) in enumerate(commit_files, 1):
            summary_text = " ".join(commit_info.get("subject", "").split()) or "(no subject)"
            body_text = " ".join(commit_info.get("body", "").split()) or "(no body provided)"

            outf.write(
                f"## Commit {idx}/{len(commit_files)} - {commit_info['short']}: {summary_text}\n"
            )
            outf.write(f"- SHA: {commit_info.get('sha', '')}\n")
            outf.write(f"- Author: {commit_info.get('author', 'unknown')}\n")
            outf.write(f"- Date: {commit_info.get('date', '')}\n")
            outf.write(f"- URL: {commit_info.get('url', '')}\n")
            outf.write(f"- Body: {body_text}\n")
            outf.write(f"- Detailed file: {commit_file}\n")
            outf.write("\n")

    print(f"✓ Created summary compilation: {output_file}")
    return True


def create_round_robin_comparisons(
    processed_commits: List[Dict[str, object]],
    output_dir: str,
    selection_requested: str,
    selection_canonical: str,
    selected_commits: List[str],
) -> List[str]:
    """Create pairwise comparison files for every commit combination."""
    print("Creating round-robin comparisons...")

    if len(processed_commits) < 2:
        print("Warning: Not enough commits for round-robin comparisons")
        return []

    output_files: List[str] = []

    for left, right in combinations(processed_commits, 2):
        left_info = left["info"]
        right_info = right["info"]
        left_sha = left_info.get("sha")
        right_sha = right_info.get("sha")
        left_files = left["files"]
        right_files = right["files"]

        if not isinstance(left_sha, str) or not isinstance(right_sha, str):
            continue
        if not isinstance(left_files, list) or not isinstance(right_files, list):
            continue

        output_file = os.path.join(
            output_dir, f"commit-{left_sha[:8]}-versus-{right_sha[:8]}.txt"
        )

        combined_files = sorted(set(left_files) | set(right_files))
        files_arg = " ".join(shlex.quote(f) for f in combined_files)
        diff_cmd = f"git diff {shlex.quote(left_sha)} {shlex.quote(right_sha)}"
        if files_arg:
            diff_cmd += f" -- {files_arg}"

        diff_output = run_command(diff_cmd)

        left_summary = " ".join(left_info.get("subject", "").split()) or "(no subject)"
        right_summary = " ".join(right_info.get("subject", "").split()) or "(no subject)"

        with open(output_file, "w", encoding="utf-8") as outf:
            outf.write(
                f"# Commit {left_sha[:8]} vs {right_sha[:8]}: "
                f"{left_summary} ↔ {right_summary}\n"
            )
            for line in selection_header_lines(
                selection_requested, selection_canonical, selected_commits
            ):
                outf.write(f"{line}\n")
            outf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            outf.write(f"# Left SHA: {left_sha}\n")
            outf.write(f"# Right SHA: {right_sha}\n")
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
        description="Automate diff generation for selected commits",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "commit_selection",
        nargs="?",
        help=(
            "Commit selection string like 'abc123,def456' or 'abc123-def456'. "
            "Accepts commas, ranges, and whitespace."
        ),
    )
    parser.add_argument(
        "--commits",
        dest="commit_selection",
        help=(
            "Alias for the commit selection string. "
            "Examples: 'abc123,def456' or 'abc123-def456'."
        ),
    )
    parser.add_argument(
        "--base-branch",
        default="main",
        help="Base branch to start from (default: main)",
    )
    parser.add_argument(
        "--remote",
        default="origin",
        help="Remote name to fetch commits from (default: origin)",
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

    if not args.commit_selection:
        parser.error("commit_selection is required (e.g. 'abc123,def456').")

    try:
        selected_commits = parse_commit_selection(args.commit_selection)
    except SelectionParseError as exc:
        parser.error(str(exc))

    selection_requested = args.commit_selection
    selection_canonical = format_commit_selection(selected_commits)
    selection_tag = build_selection_tag(selected_commits, selection_canonical)

    print(f"Requested commit selection: {selection_requested}")
    print(f"Canonical commit selection: {selection_canonical}")
    if selected_commits:
        preview = format_commit_list_preview(selected_commits)
        print(
            f"Expanded commits: count={len(selected_commits)} "
            f"first={selected_commits[0][:8]} last={selected_commits[-1][:8]} preview={preview}"
        )

    check_current_branch(args.base_branch)

    try:
        fetch_remote_branches(args.remote)

        repo_url = get_repo_url()
        repo_name = get_repo_name_with_owner()

        print(f"Collecting info for commit selection: {selection_canonical}...")
        commit_infos: List[Dict[str, str]] = []
        missing_commits: List[str] = []

        for commit in selected_commits:
            try:
                commit_info = get_commit_info(commit, repo_url)
                commit_infos.append(commit_info)
                print(f"  {commit_info['short']}: {commit_info['subject']}")
            except (subprocess.CalledProcessError, ValueError) as exc:
                print(f"  {commit[:8]}: Not found or inaccessible ({exc})")
                missing_commits.append(commit)

        if not commit_infos:
            print("Error: No valid commits found for the requested selection")
            sys.exit(1)

        successful_commits: List[Tuple[Dict[str, str], str]] = []
        successful_commits_with_logs: List[Tuple[Dict[str, str], str]] = []
        processed_commits: List[Dict[str, object]] = []
        processed_commits_with_logs: List[Dict[str, object]] = []

        for commit_info in commit_infos:
            print(f"\n--- Processing commit {commit_info['short']}: {commit_info['subject']} ---")

            files = get_commit_changed_files(commit_info["sha"])
            if not files:
                print(f"No changed files found for commit {commit_info['short']}")
                continue

            print(f"Total changed files: {len(files)}")

            included_files, _excluded_files = filter_excluded_files(files)
            if not included_files:
                print(
                    f"No files to process for commit {commit_info['short']} "
                    "(all files were excluded)"
                )
                continue

            print(
                f"Files to process ({len(included_files)}): "
                f"{', '.join(included_files)}"
            )

            try:
                checks_with_logs: List[Dict[str, str]] = []
                checks = get_commit_checks(commit_info["sha"], repo_name)
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as exc:
                print(f"Failed to retrieve checks for commit {commit_info['short']}: {exc}")
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
                args.output_dir, f"commit-{commit_info['short']}-implementation.txt"
            )
            output_file_with_logs = os.path.join(
                args.output_dir, f"commit-{commit_info['short']}-implementation-with-logs.txt"
            )
            if run_commit_big_picture(
                commit_info,
                included_files,
                checks,
                output_file,
                include_logs=False,
            ):
                successful_commits.append((commit_info, output_file))
                processed_commits.append(
                    {
                        "info": commit_info,
                        "file": output_file,
                        "files": included_files,
                    }
                )
            if run_commit_big_picture(
                commit_info,
                included_files,
                checks_with_logs,
                output_file_with_logs,
                include_logs=True,
            ):
                successful_commits_with_logs.append((commit_info, output_file_with_logs))
                processed_commits_with_logs.append(
                    {
                        "info": commit_info,
                        "file": output_file_with_logs,
                        "files": included_files,
                    }
                )

        if successful_commits:
            requested_count = len(selected_commits)
            processed_shas = {info["sha"] for info, _ in successful_commits}
            processed_count = len(processed_shas)
            skipped_commits = [commit for commit in selected_commits if commit not in processed_shas]
            print(
                f"\nRequested commit count: {requested_count}; "
                f"processed commit count: {processed_count}"
            )
            if missing_commits:
                missing_short = ", ".join(commit[:8] for commit in missing_commits)
                print(f"Missing/inaccessible commits: {missing_short}")
            if skipped_commits:
                skipped_short = ", ".join(commit[:8] for commit in skipped_commits)
                print(f"Skipped commits after processing: {skipped_short}")

            master_output = os.path.join(
                args.output_dir, f"commit-comparison-{selection_tag}.txt"
            )
            create_master_comparison(
                successful_commits,
                selection_requested,
                selection_canonical,
                selected_commits,
                master_output,
            )

            summary_output = os.path.join(
                args.output_dir, f"commit-summaries-{selection_tag}.txt"
            )
            create_summary_compilation(
                successful_commits,
                selection_requested,
                selection_canonical,
                selected_commits,
                summary_output,
            )

            touched_output = os.path.join(
                args.output_dir, f"commit-touched-files-{selection_tag}.txt"
            )
            create_touched_files_compilation(
                commit_infos,
                selection_requested,
                selection_canonical,
                selected_commits,
                touched_output,
                master_output,
            )
            round_robin_outputs = create_round_robin_comparisons(
                processed_commits,
                args.output_dir,
                selection_requested,
                selection_canonical,
                selected_commits,
            )

            print(f"\n✓ Successfully processed {len(successful_commits)} commit(s) (without logs)")
            print(f"✓ Individual files: {args.output_dir}/commit-{{sha}}-implementation.txt")
            print(f"✓ Master comparison: {master_output}")
            print(f"✓ Summary compilation: {summary_output}")
            print(f"✓ Touched files compilation: {touched_output}")
            if round_robin_outputs:
                print(
                    "✓ Round-robin comparisons: "
                    f"{args.output_dir}/commit-{{left}}-versus-{{right}}.txt"
                )
        else:
            print("\nNo commits were successfully processed (without logs)")

        if successful_commits_with_logs:
            master_output_with_logs = os.path.join(
                args.output_dir, f"commit-comparison-{selection_tag}-with-logs.txt"
            )
            create_master_comparison(
                successful_commits_with_logs,
                selection_requested,
                selection_canonical,
                selected_commits,
                master_output_with_logs,
                include_logs=True,
            )

            summary_output_with_logs = os.path.join(
                args.output_dir, f"commit-summaries-{selection_tag}-with-logs.txt"
            )
            create_summary_compilation(
                successful_commits_with_logs,
                selection_requested,
                selection_canonical,
                selected_commits,
                summary_output_with_logs,
                include_logs=True,
            )

            touched_output_with_logs = os.path.join(
                args.output_dir, f"commit-touched-files-{selection_tag}-with-logs.txt"
            )
            create_touched_files_compilation(
                commit_infos,
                selection_requested,
                selection_canonical,
                selected_commits,
                touched_output_with_logs,
                master_output_with_logs,
                include_logs=True,
            )

            print(f"\n✓ Successfully processed {len(successful_commits_with_logs)} commit(s) (with logs)")
            print(
                f"✓ Individual files (with logs): {args.output_dir}/commit-{{sha}}-implementation-with-logs.txt"
            )
            print(f"✓ Master comparison (with logs): {master_output_with_logs}")
            print(f"✓ Summary compilation (with logs): {summary_output_with_logs}")
            print(f"✓ Touched files compilation (with logs): {touched_output_with_logs}")
        else:
            print("\nNo commits were successfully processed (with logs)")

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
