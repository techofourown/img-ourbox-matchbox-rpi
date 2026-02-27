#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd tar
need_cmd oras
need_cmd find

REF_FILE="${ROOT}/contracts/airgap-platform.ref"
[[ -f "${REF_FILE}" ]] || die "Missing ${REF_FILE}"
REF="$(cat "${REF_FILE}")"

OUT="${ROOT}/artifacts/airgap"
PULL_DIR="${ROOT}/artifacts/.airgap-platform-pull"
META_DIR="${ROOT}/artifacts/.airgap-platform-meta"

log "Using airgap platform ref: ${REF}"

# Refuse to overwrite existing artifacts unless operator confirms
if [[ -d "${OUT}" ]] && find "${OUT}" -mindepth 1 -print -quit >/dev/null 2>&1; then
  log "ERROR: Existing artifacts detected in ${OUT} (refusing to overwrite)"
  find "${OUT}" -maxdepth 2 -type f -print | sed 's/^/  /'
  echo
  log "You can remove them manually, or allow this script to remove them."
  read -r -p "Type REMOVE to delete ${OUT} and continue, or anything else to abort: " confirm
  if [[ "${confirm}" != "REMOVE" ]]; then
    die "Fetch aborted; existing artifacts not removed"
  fi

  log "WARNING: About to remove ${OUT}"
  if [[ -w "${OUT}" ]]; then
    rm -rf "${OUT}" || die "Failed to remove ${OUT}"
  else
    need_cmd sudo
    sudo rm -rf "${OUT}" || die "Failed to remove ${OUT} (sudo)"
  fi
fi

rm -rf "${PULL_DIR}" "${META_DIR}"
mkdir -p "${PULL_DIR}" "${META_DIR}" "${OUT}"

log "Pulling airgap platform bundle"
oras pull "${REF}" -o "${PULL_DIR}" | tee "${META_DIR}/oras.pull.log"

TARBALL="${PULL_DIR}/dist/airgap-platform.tar.gz"
[[ -f "${TARBALL}" ]] || {
  echo "Expected ${TARBALL} not found. Pulled files:" >&2
  find "${PULL_DIR}" -maxdepth 4 -type f -print >&2 || true
  exit 1
}

log "Extracting bundle into ${OUT}"
tar -xzf "${TARBALL}" -C "${OUT}"

# Basic validation
[[ -x "${OUT}/k3s/k3s" ]] || die "Missing k3s binary in ${OUT}/k3s/k3s"
[[ -f "${OUT}/manifest.env" ]] || die "Missing manifest.env in ${OUT}"

shopt -s nullglob
k3s_tars=("${OUT}/k3s/k3s-airgap-images-"*.tar)
platform_tars=("${OUT}/platform/images/"*.tar)
shopt -u nullglob

(( ${#k3s_tars[@]} > 0 )) || die "No k3s airgap image tar found in ${OUT}/k3s"
(( ${#platform_tars[@]} > 0 )) || die "No platform image tars found in ${OUT}/platform/images"

log "Artifacts created:"
ls -lah "${OUT}/k3s" "${OUT}/platform/images" "${OUT}/manifest.env"

log "Fetching pinned platform contract (OCI artifact)"
"${ROOT}/tools/fetch-platform-contract.sh"

log "Syncing pinned platform contract into pi-gen stage files"
"${ROOT}/tools/sync-platform-contract-into-pigen.sh"
