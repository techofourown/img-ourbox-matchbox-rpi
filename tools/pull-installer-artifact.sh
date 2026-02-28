#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd oras
need_cmd sha256sum
need_cmd awk

: "${OURBOX_TARGET:=rpi}"
: "${INSTALLER_REPO:=ghcr.io/techofourown/ourbox-matchbox-installer}"
: "${INSTALLER_CHANNEL:=stable}"
: "${INSTALLER_REGISTRY_USERNAME:=}"
: "${INSTALLER_REGISTRY_PASSWORD:=}"

usage() {
  cat <<EOF
Usage:
  $0 [--ref REF] [--outdir DIR]
  $0 --channel CHANNEL [--outdir DIR]
  $0 --latest [--outdir DIR]

Defaults:
  --channel stable
  --outdir deploy-installer-from-registry
  REF from channel: \${INSTALLER_REPO}:\${OURBOX_TARGET}-installer-\${CHANNEL}
EOF
}

maybe_login() {
  local ref="$1"
  if [[ -n "${INSTALLER_REGISTRY_USERNAME}" ]]; then
    local registry="${ref%%/*}"
    log "Logging into ${registry} for pull"
    oras login "${registry}" -u "${INSTALLER_REGISTRY_USERNAME}" --password "${INSTALLER_REGISTRY_PASSWORD:-}"
  fi
}

REF=""
OUTDIR="deploy-installer-from-registry"
CHANNEL="${INSTALLER_CHANNEL}"
USE_LATEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      REF="$2"
      shift 2
      ;;
    --channel)
      [[ $# -ge 2 ]] || die "--channel requires a value"
      CHANNEL="$2"
      shift 2
      ;;
    --outdir)
      [[ $# -ge 2 ]] || die "--outdir requires a value"
      OUTDIR="$2"
      shift 2
      ;;
    --latest)
      USE_LATEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -n "${REF}" && "${USE_LATEST}" == "1" ]]; then
  die "use either --ref or --latest, not both"
fi

if [[ "${USE_LATEST}" == "1" ]]; then
  REF_FILE="${ROOT}/deploy/installer-artifact.pinned.ref"
  if [[ ! -f "${REF_FILE}" ]]; then
    REF_FILE="${ROOT}/deploy/installer-artifact.ref"
  fi
  [[ -f "${REF_FILE}" ]] || die "${REF_FILE} not found. Run ./tools/publish-installer-artifact.sh deploy first, or pass --ref."
  REF="$(cat "${REF_FILE}")"
fi

if [[ -z "${REF}" ]]; then
  REF="${INSTALLER_REPO}:${OURBOX_TARGET}-installer-${CHANNEL}"
fi

mkdir -p "${OUTDIR}"

log ">> Pull installer: ${REF}"
maybe_login "${REF}"
oras pull "${REF}" -o "${OUTDIR}"

if [[ ! -f "${OUTDIR}/installer.img.xz" ]]; then
  die "oras pull succeeded but ${OUTDIR}/installer.img.xz missing"
fi

[[ -f "${OUTDIR}/installer.img.xz.sha256" ]] || die "missing ${OUTDIR}/installer.img.xz.sha256"
expected="$(awk 'NF>=1 {print $1; exit}' "${OUTDIR}/installer.img.xz.sha256")"
expected="${expected,,}"
[[ "${expected}" =~ ^[0-9a-f]{64}$ ]] || die "invalid sha256 in installer.img.xz.sha256"
actual="$(sha256sum "${OUTDIR}/installer.img.xz" | awk '{print $1}')"
[[ "${expected}" == "${actual}" ]] || die "sha mismatch (expected ${expected}, got ${actual})"
log "sha256 verified: ${actual}"

log "DONE: extracted installer artifact files:"
ls -lah "${OUTDIR}"
