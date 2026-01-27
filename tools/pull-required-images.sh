#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

: "${BUILDKIT_VERSION:=v0.23.2}"

cli="$(pick_container_cli)"
cli_b="$(cli_base "${cli}")"

pull_and_tag() {
  local src="$1" dst="$2"
  log ">> Pull: ${src}"
  # shellcheck disable=SC2086
  $cli pull "${src}"
  log ">> Tag:  ${src} -> ${dst}"
  # shellcheck disable=SC2086
  $cli tag "${src}" "${dst}"
}

# pi-gen Dockerfile build arg uses "debian:trixie"
if ! pull_and_tag "$(imgref mirror/debian trixie)" "debian:trixie"; then
  log "Mirror pull failed; falling back to docker.io for debian:trixie"
  pull_and_tag "docker.io/library/debian:trixie" "debian:trixie"
fi

# Only needed for nerdctl buildkitd container workflow
if [[ "${cli_b}" == "nerdctl" ]]; then
  if ! pull_and_tag "$(imgref mirror/buildkit "${BUILDKIT_VERSION}")" "moby/buildkit:${BUILDKIT_VERSION}"; then
    log "Mirror pull failed; falling back to docker.io for moby/buildkit:${BUILDKIT_VERSION}"
    pull_and_tag "docker.io/moby/buildkit:${BUILDKIT_VERSION}" "moby/buildkit:${BUILDKIT_VERSION}"
  fi
fi
