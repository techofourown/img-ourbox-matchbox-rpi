#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/installer-ssh-helper.upstream.env"

need_cmd curl
need_cmd diff

VENDORED_HELPER="${ROOT}/tools/installer-ssh-helper.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
UPSTREAM_HELPER="${TMP}/installer-ssh-helper.sh"
UPSTREAM_URL="https://raw.githubusercontent.com/${SW_OURBOX_OS_REPO}/${SW_OURBOX_OS_REVISION}/${SW_OURBOX_OS_PATH}"

log "Fetching upstream installer SSH helper: ${UPSTREAM_URL}"
curl -fsSL "${UPSTREAM_URL}" -o "${UPSTREAM_HELPER}" \
  || die "failed to fetch upstream installer SSH helper"

diff -u "${UPSTREAM_HELPER}" "${VENDORED_HELPER}" \
  || die "vendored installer SSH helper drifted from ${SW_OURBOX_OS_REPO}@${SW_OURBOX_OS_REVISION}"

log "Vendored installer SSH helper matches ${SW_OURBOX_OS_REPO}@${SW_OURBOX_OS_REVISION}"
