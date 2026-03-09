#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/release-control.upstream.env"

need_cmd curl
need_cmd diff

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

while IFS= read -r relpath; do
  [[ -n "${relpath}" ]] || continue
  local_path="${ROOT}/tools/release-control/${relpath}"
  upstream_path="${SW_OURBOX_OS_RELEASE_CONTROL_BASE}/${relpath}"
  upstream_url="https://raw.githubusercontent.com/${SW_OURBOX_OS_REPO}/${SW_OURBOX_OS_REVISION}/${upstream_path}"
  fetched_path="${TMP}/${relpath}"

  log "Fetching upstream release-control file: ${upstream_url}"
  curl -fsSL "${upstream_url}" -o "${fetched_path}" \
    || die "failed to fetch upstream release-control file ${upstream_path}"

  diff -u "${fetched_path}" "${local_path}" \
    || die "vendored release-control file ${relpath} drifted from ${SW_OURBOX_OS_REPO}@${SW_OURBOX_OS_REVISION}"
done <<< "${SW_OURBOX_OS_RELEASE_CONTROL_FILES}"

log "Vendored release-control module matches ${SW_OURBOX_OS_REPO}@${SW_OURBOX_OS_REVISION}"
