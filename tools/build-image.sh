#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"

# Pick a container CLI (caller can override with DOCKER=...)
DOCKER="${DOCKER:-$(pick_container_cli)}"
export DOCKER

# If we're using nerdctl, we need buildkitd running.
ensure_buildkitd

# Ensure build dependencies are pulled from OUR registry and tagged to the names vendor expects.
"${ROOT}/tools/pull-required-images.sh"

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
