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

mirror_image "docker.io/library/debian:trixie" "$(imgref mirror/debian trixie)"
mirror_image "docker.io/moby/buildkit:${BUILDKIT_VERSION}" "$(imgref mirror/buildkit "${BUILDKIT_VERSION}")"
