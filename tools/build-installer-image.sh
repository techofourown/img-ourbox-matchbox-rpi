#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"

cd "${ROOT}"

mkdir -p "${ROOT}/deploy"
if [[ ! -w "${ROOT}/deploy" ]]; then
  if command -v sudo >/dev/null 2>&1; then
    log "deploy/ not writable; fixing ownership with sudo"
    sudo chown -R "$(id -u):$(id -g)" "${ROOT}/deploy"
  fi
fi
[[ -w "${ROOT}/deploy" ]] || die "deploy/ is not writable: ${ROOT}/deploy"

BUILD_MARKER="${ROOT}/deploy/.installer-build-start"
: > "${BUILD_MARKER}"

DOCKER="${DOCKER:-$(pick_container_cli)}"
export DOCKER

SUDO=""
if [[ ${EUID} -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo -E"
fi

ensure_buildkitd

ensure_payload() {
  local payload
  payload="$(ls -1t "${ROOT}"/deploy/img-ourbox-matchbox-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
  if [[ -n "${payload}" && -f "${payload}" ]]; then
    return 0
  fi

  log "No target OS payload found in deploy/. Building via tools/build-image.sh"
  : "${OURBOX_VARIANT:=dev}"
  : "${OURBOX_VERSION:=dev}"
  OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" "${ROOT}/tools/build-image.sh"

  payload="$(ls -1t "${ROOT}"/deploy/img-ourbox-matchbox-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
  [[ -n "${payload}" && -f "${payload}" ]] || die "build-image.sh did not produce deploy/img-ourbox-matchbox-rpi-*.img.xz"
}

ensure_payload

: "${OURBOX_TARGET:=rpi}"
: "${OURBOX_MODEL_ID:=TOO-OBX-MBX-01}"
: "${OURBOX_SKU_ID:=TOO-OBX-MBX-BASE-001}"
: "${OURBOX_VARIANT:=dev}"
: "${OURBOX_VERSION:=dev}"

export PIGEN_DOCKER_OPTS="${PIGEN_DOCKER_OPTS:-} \
  --volume ${ROOT}:/ourbox:ro \
  --volume ${ROOT}/pigen/overrides/stage2/SKIP_IMAGES:/pi-gen/stage2/SKIP_IMAGES:ro \
  -e OURBOX_VARIANT=${OURBOX_VARIANT} \
  -e OURBOX_VERSION=${OURBOX_VERSION} \
  -e OURBOX_MODEL_ID=${OURBOX_MODEL_ID} \
  -e OURBOX_SKU_ID=${OURBOX_SKU_ID} \
  -e OURBOX_TARGET=${OURBOX_TARGET}"

log "Building installer image with pigen/config/ourbox-installer.conf"
if [[ "$(cli_base "${DOCKER}")" == "podman" && "${DOCKER}" == *" "* && -n "${SUDO}" ]]; then
  DOCKER=podman ${SUDO} "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox-installer.conf"
else
  "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox-installer.conf"
fi

log "Collecting build artifacts into ${ROOT}/deploy"
move_into_deploy() {
  local src="$1"
  local dst="${ROOT}/deploy/$(basename "${src}")"

  if mv -f "${src}" "${dst}" 2>/dev/null; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo mv -f "${src}" "${dst}"
    return 0
  fi
  die "Failed to move ${src} -> ${dst}"
}

shopt -s nullglob
for f in "${ROOT}"/img-*; do
  [[ -f "${f}" ]] || continue
  [[ "${f}" -nt "${BUILD_MARKER}" ]] || continue

  case "${f}" in
    *.img.xz|*.img|*.zip|*.info|*.bmap|*.sha256)
      log "Moving artifact: $(basename "${f}") -> deploy/"
      move_into_deploy "${f}"
      ;;
  esac
done
shopt -u nullglob

if command -v sudo >/dev/null 2>&1; then
  sudo chown -R "$(id -u):$(id -g)" "${ROOT}/deploy" >/dev/null 2>&1 || true
fi

need_cmd xz
installer_img="$(ls -1t "${ROOT}"/deploy/img-ourbox-matchbox-installer-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${installer_img}" && -f "${installer_img}" ]] || die "build did not produce deploy/img-ourbox-matchbox-installer-rpi-*.img.xz"
[[ "${installer_img}" -nt "${BUILD_MARKER}" ]] || die "installer image exists but is not from this build"
xz -t "${installer_img}"

log "Installer build OK: ${installer_img}"
