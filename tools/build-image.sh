#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"
: "${NGINX_IMAGE:=docker.io/library/nginx:1.27-alpine}"
NGINX_IMAGE="$(canonicalize_image_ref "${NGINX_IMAGE}")"
NGINX_TAR="$(echo "${NGINX_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"

# Pick a container CLI (caller can override with DOCKER=...)
DOCKER="${DOCKER:-$(pick_container_cli)}"
export DOCKER

SUDO=""
if [[ ${EUID} -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo -E"
fi

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

log "Preflight: verifying airgap artifacts exist"
[[ -x "${ROOT}/artifacts/airgap/k3s/k3s" ]] || die "missing k3s binary; run ./tools/fetch-airgap-platform.sh"
[[ -f "${ROOT}/artifacts/airgap/k3s/k3s-airgap-images-arm64.tar" ]] || die "missing k3s airgap tar; run ./tools/fetch-airgap-platform.sh"
[[ -f "${ROOT}/artifacts/airgap/platform/images/${NGINX_TAR}" ]] || die "missing nginx tar; run ./tools/fetch-airgap-platform.sh"

if [[ "$(cli_base "${DOCKER}")" == "podman" && "${DOCKER}" == *" "* && -n "${SUDO}" ]]; then
  log "NOTE: running pi-gen under sudo with DOCKER=podman (avoids sudo-in-DOCKER quoting issues)"
  DOCKER=podman ${SUDO} "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox.conf"
else
  "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox.conf"
fi

log "Postflight: validating deploy outputs"
IMG_XZ="$(ls -1 "${ROOT}/deploy"/img-*.img.xz | head -n 1 || true)"
[[ -n "${IMG_XZ}" && -f "${IMG_XZ}" ]] || die "build did not produce deploy/img-*.img.xz"

need_cmd xz
xz -t "${IMG_XZ}"

log "Build OK: ${IMG_XZ}"
log "Next: ./tools/publish-os-artifact.sh deploy"
