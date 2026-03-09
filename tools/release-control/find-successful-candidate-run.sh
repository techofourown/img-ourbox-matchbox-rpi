#!/usr/bin/env bash
# Resolve the latest successful candidate workflow run for a source commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/release-control/lib.sh"

need_cmd gh
need_cmd python3

WORKFLOW_NAME="${1:?Usage: find-successful-candidate-run.sh <workflow-name> <source-commit>}"
SOURCE_COMMIT="${2:?Usage: find-successful-candidate-run.sh <workflow-name> <source-commit>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
NO_MATCH_EXIT=3

json="$(gh run list --repo "${REPO}" --workflow "${WORKFLOW_NAME}" --branch main --event push \
  --json databaseId,headSha,status,conclusion,createdAt -L "${RUN_LIST_LIMIT:-100}")" \
  || die "Unable to list workflow runs for ${WORKFLOW_NAME}"

run_id="$(
  python3 -c 'import json,sys
source_commit = sys.argv[1]
runs = json.load(sys.stdin)
matches = [
    run for run in runs
    if run.get("headSha") == source_commit
    and run.get("status") == "completed"
    and run.get("conclusion") == "success"
]
matches.sort(key=lambda run: run.get("createdAt") or "", reverse=True)
print(matches[0]["databaseId"] if matches else "")' \
    "${SOURCE_COMMIT}" <<<"${json}"
)"

if [[ -n "${run_id}" ]]; then
  printf '%s\n' "${run_id}"
  exit 0
fi

exit "${NO_MATCH_EXIT}"
