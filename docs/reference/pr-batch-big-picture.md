# PR Batch Big Picture

- Status: Draft
- Audience: maintainers, reviewers, consultant-packet builders
- Related:
  - `../../.github/workflows/pr-batch-big-picture.yml`
  - `../../tools/pr_batch_big_picture.py`

## 1. Purpose

This document explains how to use the repo-local PR batch comparison workflow and tool.

It exists for cases where a maintainer needs one artifact set that compares multiple pull requests
at once, including:

- per-PR diffs against a base branch
- PR comments and review activity
- status-check summaries
- failed-check logs
- touched-file context on the base branch
- pairwise PR-to-PR comparisons

This is a repo-owned workflow and tool. It is not a reusable GitHub Action intended for other
repositories.

## 2. Entrypoints

There are two supported entrypoints.

### 2.1 GitHub Actions

Workflow:

- `/.github/workflows/pr-batch-big-picture.yml`

This is the normal remote path when you want GitHub-hosted execution and an uploaded artifact bundle.

### 2.2 Local CLI

Tool:

- `/tools/pr_batch_big_picture.py`

This is the right path when you want to iterate locally, inspect output immediately, or generate a
packet outside the workflow UI.

## 3. Inputs

The workflow and CLI both use the same core inputs.

- `pr_selection`
  - required
  - comma-separated PRs and/or inclusive ranges
  - examples:
    - `123`
    - `123,127,130`
    - `123-130`
    - `123-130,135,140-142`
- `base_branch`
  - optional
  - defaults to `main`
- `remote`
  - optional
  - defaults to `origin` in the workflow and CLI unless overridden

Selection parsing accepts:

- commas
- inclusive numeric ranges
- optional `#` prefixes
- surrounding whitespace

## 4. Local Usage

Local runs must start from the chosen base branch.

Example:

```bash
git checkout main
python tools/pr_batch_big_picture.py \
  "77-80" \
  --base-branch "main" \
  --remote "github" \
  --output-dir "/tmp/pr-batch-77-80"
```

Local prerequisites:

- `gh` must be installed and authenticated
- the repo must have the requested remote configured
- the base branch must exist locally
- the selected PR branches or PR refs must be fetchable

## 5. Workflow Usage

Run the `PR Batch Big Picture` workflow manually from the Actions tab and provide:

- `pr_selection`
- optionally `base_branch`
- optionally `remote`

The workflow checks out the chosen base branch, runs the tool, and uploads the generated outputs as
an Actions artifact.

## 6. Outputs

The tool writes a family of text artifacts into the requested output directory.

Per-PR outputs:

- `pr-<num>-implementation.txt`
- `pr-<num>-implementation-with-logs.txt`

Cross-PR outputs:

- `pr-comparison-<selection-tag>.txt`
- `pr-comparison-<selection-tag>-with-logs.txt`
- `pr-summaries-<selection-tag>.txt`
- `pr-summaries-<selection-tag>-with-logs.txt`
- `pr-touched-files-<selection-tag>.txt`
- `pr-touched-files-<selection-tag>-with-logs.txt`
- `pr-<left>-versus-<right>.txt`

`selection-tag` is derived from:

- min PR number
- max PR number
- selected PR count
- short hash of the canonical selection string

Example:

- `77-80-4prs-<hash>`

## 7. What Each Artifact Contains

### 7.1 Per-PR implementation files

Each per-PR file includes:

- explicit PR number metadata
- PR metadata
- diff against the chosen base branch
- status checks
- comment and review activity
- optionally failed-check logs in the `with-logs` variant

### 7.2 Master comparison

The master comparison concatenates all processed per-PR implementation files into one reviewable
document.

### 7.3 Summary compilation

The summary file keeps only high-level PR metadata and pointers to the detailed output files.

### 7.4 Touched files compilation

The touched-files compilation shows the base-branch contents of unique changed paths across the
selection.

Important behavior:

- it uses the full changed-path set, not just included diff paths
- deleted or excluded files still appear here if they exist on the base branch
- each touched file records which PR numbers introduced it into the compilation

### 7.5 Round-robin comparisons

The round-robin files compare every processed PR pair against each other using the union of their
included file paths.

Important behavior:

- if a PR pair has no included files to compare, that round-robin output is skipped
- this prevents falling back to an unrestricted branch-to-branch diff

## 8. Comment And Review Coverage

The generated comment stream includes:

- top-level issue comments
- review summary comments
- inline review comments
- replies to inline review comments
- bare `APPROVED` review actions
- bare `CHANGES_REQUESTED` review actions

It does not currently try to model every possible review-state transition as a separate timeline
artifact beyond those comment-bearing or decision-bearing events.

## 9. Exclusion Rules

Some files are intentionally excluded from diff-heavy outputs.

Current exclusion behavior:

- `package-lock.json` is excluded from per-PR diffs and round-robin path sets

Important nuance:

- excluded-only PRs are still processed
- their metadata, checks, comments, and reviews are still captured
- their touched files still appear in touched-files output when the path exists on the base branch

## 10. Logs

The `with-logs` outputs include raw logs for failed GitHub Actions checks when a run ID can be
resolved from the check URL.

This is intended for diagnosis and consultant packets. It can make the combined artifacts much
larger.

## 11. Troubleshooting

Common failure cases:

- invalid `pr_selection`
  - use a form like `123-130,135,140-142`
- wrong starting branch for a local run
  - the tool must start on the chosen `base_branch`
- inaccessible PRs
  - check `gh auth status`
  - confirm the repo and remote are correct
- missing branch checkout
  - ensure the PR head branch or PR ref is fetchable from the chosen remote
- empty diff for a processed PR
  - this can be legitimate if all changed files were excluded

## 12. Recommendation

Use the workflow when you want a durable uploaded artifact bundle.

Use the local CLI when you are refining the selection, testing tool behavior, or assembling a
packet interactively.
