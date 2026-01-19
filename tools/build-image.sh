#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pick a container CLI
if [ -z "${DOCKER:-}" ]; then
  if command -v docker >/dev/null 2>&1; then
    DOCKER=docker
  elif command -v nerdctl >/dev/null 2>&1; then
    DOCKER=nerdctl
  elif command -v podman >/dev/null 2>&1; then
    DOCKER=podman
  else
    echo "No container CLI found (need docker, nerdctl, or podman)." >&2
    exit 1
  fi
fi
export DOCKER

# Defaults (override by prefixing env vars when invoking)
: "${OURBOX_TARGET:=rpi}"
: "${OURBOX_SKU:=TOO-OBX-MINI-01}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"

# Mount the repo so STAGE_LIST can reference /ourbox/...
# Also suppress the upstream stage2 export so we only ship the OurBox artifact.
export PIGEN_DOCKER_OPTS="${PIGEN_DOCKER_OPTS:-} \
  --volume ${ROOT}:/ourbox:ro \
  --volume ${ROOT}/pigen/overrides/stage2/SKIP_IMAGES:/pi-gen/stage2/SKIP_IMAGES:ro \
  -e OURBOX_TARGET=${OURBOX_TARGET} \
  -e OURBOX_SKU=${OURBOX_SKU} \
  -e OURBOX_VARIANT=${OURBOX_VARIANT} \
  -e OURBOX_VERSION=${OURBOX_VERSION}"

exec "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox.conf"
