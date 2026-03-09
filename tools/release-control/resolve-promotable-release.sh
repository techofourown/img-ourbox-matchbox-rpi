#!/usr/bin/env bash
# Resolve the authorized GitHub Release tag for a candidate source commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/release-control/lib.sh"

need_cmd git
need_cmd gh
need_cmd python3

PROMOTION_CONTEXT="${1:?Usage: resolve-promotable-release.sh <stable|exp-labs|versioned> <source-commit>}"
SOURCE_COMMIT="${2:?Usage: resolve-promotable-release.sh <stable|exp-labs|versioned> <source-commit>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
NO_MATCH_EXIT=3

resolve_source_commit() {
  local release_ref="$1"
  local commit subject

  commit="$(git -C "${ROOT}" rev-parse "${release_ref}^{commit}" 2>/dev/null)" \
    || die "Unable to resolve commit for release ref ${release_ref}"
  subject="$(git -C "${ROOT}" log -1 --format=%s "${commit}" 2>/dev/null || true)"

  if [[ "${subject}" == chore\(release\):* ]]; then
    git -C "${ROOT}" rev-parse "${commit}^" 2>/dev/null \
      || die "Unable to resolve source commit behind release commit ${commit}"
  else
    printf '%s\n' "${commit}"
  fi
}

release_matches_context() {
  local is_draft="$1" is_prerelease="$2"

  case "${PROMOTION_CONTEXT}" in
    stable|versioned)
      [[ "${is_draft}" == "false" && "${is_prerelease}" == "false" ]]
      ;;
    exp-labs)
      [[ "${is_draft}" == "false" && "${is_prerelease}" == "true" ]]
      ;;
    *)
      die "Unknown promotion context: ${PROMOTION_CONTEXT} (expected: stable|exp-labs|versioned)"
      ;;
  esac
}

json="$(gh release list --repo "${REPO}" --json tagName,isDraft,isPrerelease -L "${RELEASE_LIST_LIMIT:-100}")" \
  || die "Unable to list GitHub releases for ${REPO}"

while IFS=$'\t' read -r release_tag is_draft is_prerelease; do
  [[ -n "${release_tag}" ]] || continue

  resolved_commit="$(resolve_source_commit "refs/tags/${release_tag}")"
  [[ "${resolved_commit}" == "${SOURCE_COMMIT}" ]] || continue
  if release_matches_context "${is_draft}" "${is_prerelease}"; then
    printf '%s\n' "${release_tag}"
    exit 0
  fi
done < <(
  python3 -c 'import json,sys
for release in json.load(sys.stdin):
    print("\t".join([
        release.get("tagName", ""),
        str(release.get("isDraft", False)).lower(),
        str(release.get("isPrerelease", False)).lower(),
    ]))' <<<"${json}"
)

exit "${NO_MATCH_EXIT}"
