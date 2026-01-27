#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"

CLI="$(pick_container_cli)"

if [[ "${1:-}" == "--latest" ]]; then
  shift
  OUTDIR="${1:-deploy-from-registry}"

  REF_FILE="${ROOT}/deploy/os-artifact.ref"
  if [[ -f "${REF_FILE}" ]]; then
    IMAGE="$(cat "${REF_FILE}")"
  else
    die "${REF_FILE} not found. Run ./tools/publish-os-artifact.sh deploy first, or pass IMAGE_REF explicitly."
  fi
else
  IMAGE="${1:-}"
  OUTDIR="${2:-deploy-from-registry}"
  [[ -n "${IMAGE}" ]] || die "Usage: $0 IMAGE_REF [OUTDIR]  or  $0 --latest [OUTDIR]"
fi

# Make sure we can pull
log ">> Pull: ${IMAGE}"
# shellcheck disable=SC2086
$CLI pull "${IMAGE}"

tmp="ourbox_os_artifact_$$"
# clean any old
# shellcheck disable=SC2086
$CLI rm -f "${tmp}" >/dev/null 2>&1 || true

# Scratch image may have no CMD; provide a dummy command so create always succeeds.
log ">> Create temp container: ${tmp}"
# shellcheck disable=SC2086
$CLI create --name "${tmp}" "${IMAGE}" /bin/true >/dev/null

mkdir -p "${OUTDIR}"

log ">> Extracting /artifact -> ${OUTDIR}"
# shellcheck disable=SC2086
$CLI cp "${tmp}:/artifact/." "${OUTDIR}/"

# cleanup
# shellcheck disable=SC2086
$CLI rm -f "${tmp}" >/dev/null

log "DONE: extracted artifact files:"
ls -lah "${OUTDIR}"
