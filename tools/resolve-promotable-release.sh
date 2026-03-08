#!/usr/bin/env bash
# Resolve the authorized GitHub Release tag for a candidate source commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd git
need_cmd gh
need_cmd python3

PROMOTION_CONTEXT="${1:?Usage: resolve-promotable-release.sh stable|exp-labs <source-commit>}"
SOURCE_COMMIT="${2:?Usage: resolve-promotable-release.sh stable|exp-labs <source-commit>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

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
    stable)
      [[ "${is_draft}" == "false" && "${is_prerelease}" == "false" ]]
      ;;
    exp-labs)
      [[ "${is_draft}" == "false" && "${is_prerelease}" == "true" ]]
      ;;
    *)
      die "Unknown promotion context: ${PROMOTION_CONTEXT} (expected: stable|exp-labs)"
      ;;
  esac
}

while IFS= read -r tag; do
  [[ -n "${tag}" ]] || continue

  resolved_commit="$(resolve_source_commit "${tag}" 2>/dev/null || true)"
  [[ -n "${resolved_commit}" && "${resolved_commit}" == "${SOURCE_COMMIT}" ]] || continue

  json="$(gh release view "${tag}" --repo "${REPO}" --json tagName,isDraft,isPrerelease 2>/dev/null || true)"
  [[ -n "${json}" ]] || continue

  read -r release_tag is_draft is_prerelease < <(
    python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["tagName"], str(data["isDraft"]).lower(), str(data["isPrerelease"]).lower())' \
      <<<"${json}"
  )

  if release_matches_context "${is_draft}" "${is_prerelease}"; then
    printf '%s\n' "${release_tag}"
    exit 0
  fi
done < <(git -C "${ROOT}" tag -l 'v*' --sort=-creatordate)

exit 1
