#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

TARGET_DEV="${1:-}"
if [[ $# -ne 1 || -z "${TARGET_DEV}" ]]; then
  die "Usage: $0 /dev/disk/by-id/<sd-or-usb>"
fi

: "${OURBOX_VARIANT:=dev}"
: "${OURBOX_VERSION:=dev}"

"${ROOT}/tools/bootstrap-host.sh"
"${ROOT}/tools/fetch-airgap-platform.sh"
OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" "${ROOT}/tools/build-image.sh"
OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" "${ROOT}/tools/build-installer-image.sh"

installer_img="$(ls -1t "${ROOT}"/deploy/img-ourbox-matchbox-installer-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${installer_img}" && -f "${installer_img}" ]] || die "No installer image found at deploy/img-ourbox-matchbox-installer-rpi-*.img.xz"

"${ROOT}/tools/flash-installer-media.sh" "${installer_img}" "${TARGET_DEV}"

log "Done. Move installer media to the Pi, boot, follow prompts, wait for power off, remove media, then boot from NVMe."
