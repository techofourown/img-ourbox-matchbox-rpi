#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /dev/disk/by-id/<sd-or-usb>"
fi

TARGET_DEV="$1"

cd "${ROOT}"

./tools/bootstrap-host.sh
./tools/fetch-airgap-platform.sh

: "${OURBOX_VARIANT:=dev}"
: "${OURBOX_VERSION:=dev}"
OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" ./tools/build-image.sh
OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" ./tools/build-installer-image.sh

installer_img="$(ls -1t "${ROOT}"/deploy/img-ourbox-matchbox-installer-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${installer_img}" && -f "${installer_img}" ]] || die "missing deploy/img-ourbox-matchbox-installer-rpi-*.img.xz"

./tools/flash-installer-media.sh "${installer_img}" "${TARGET_DEV}"

log "Done. Move installer media to the Pi, boot it, follow prompts, then remove media and boot NVMe."
