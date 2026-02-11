#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"

: "${OURBOX_TARGET:=rpi}"

cd "${ROOT}"
mkdir -p "${ROOT}/deploy"
if [[ ! -w "${ROOT}/deploy" ]]; then
  if command -v sudo >/dev/null 2>&1; then
    log "deploy/ not writable; fixing ownership with sudo"
    sudo chown -R "$(id -u):$(id -g)" "${ROOT}/deploy"
  fi
fi
[[ -w "${ROOT}/deploy" ]] || die "deploy/ is not writable: ${ROOT}/deploy"

shopt -s nullglob
payloads=("${ROOT}"/deploy/img-ourbox-matchbox-${OURBOX_TARGET,,}-*.img.xz)
shopt -u nullglob
if [[ "${#payloads[@]}" -eq 0 ]]; then
  log "No OS payload found; running ./tools/build-image.sh"
  OURBOX_TARGET="${OURBOX_TARGET}" "${ROOT}/tools/build-image.sh"
fi

shopt -s nullglob
payloads=("${ROOT}"/deploy/img-ourbox-matchbox-${OURBOX_TARGET,,}-*.img.xz)
shopt -u nullglob
[[ "${#payloads[@]}" -gt 0 ]] || die "missing deploy/img-ourbox-matchbox-${OURBOX_TARGET,,}-*.img.xz after build-image"

BUILD_MARKER="${ROOT}/deploy/.build-installer-start"
: > "${BUILD_MARKER}"

DOCKER="${DOCKER:-$(pick_container_cli)}"
export DOCKER
SUDO=""
if [[ ${EUID} -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo -E"
fi

ensure_buildkitd

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

if [[ "$(cli_base "${DOCKER}")" == "podman" && "${DOCKER}" == *" "* && -n "${SUDO}" ]]; then
  DOCKER=podman ${SUDO} "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox-installer.conf"
else
  "${ROOT}/vendor/pi-gen/build-docker.sh" -c "${ROOT}/pigen/config/ourbox-installer.conf"
fi

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
  die "failed to move ${src} -> ${dst}"
}

shopt -s nullglob
for f in "${ROOT}"/installer-*; do
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

if [[ -f "${ROOT}/build.log" && "${ROOT}/build.log" -nt "${BUILD_MARKER}" ]]; then
  if cp -f "${ROOT}/build.log" "${ROOT}/deploy/build-installer.log" 2>/dev/null; then
    :
  elif command -v sudo >/dev/null 2>&1; then
    sudo cp -f "${ROOT}/build.log" "${ROOT}/deploy/build-installer.log" >/dev/null 2>&1 || true
  fi
fi

if command -v sudo >/dev/null 2>&1; then
  sudo chown -R "$(id -u):$(id -g)" "${ROOT}/deploy" >/dev/null 2>&1 || true
fi

installer_img="$(ls -1t "${ROOT}"/deploy/installer-ourbox-matchbox-${OURBOX_TARGET,,}-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${installer_img}" && -f "${installer_img}" ]] || die "build did not produce deploy/installer-ourbox-matchbox-${OURBOX_TARGET,,}-*.img.xz"
[[ "${installer_img}" -nt "${BUILD_MARKER}" ]] || die "installer artifact is stale (not from this run): ${installer_img}"

xz -t "${installer_img}"
log "Installer image ready: ${installer_img}"
