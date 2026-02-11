#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [[ $# -ne 1 ]]; then
  die "Usage: $0 /dev/disk/by-id/<sd-or-usb>"
fi

TARGET_DEV="$1"

: "${OURBOX_VARIANT:=dev}"
: "${OURBOX_VERSION:=dev}"
export OURBOX_VARIANT OURBOX_VERSION

cd "${ROOT}"

./tools/bootstrap-host.sh
./tools/fetch-airgap-platform.sh
./tools/build-image.sh
./tools/build-installer-image.sh

INSTALLER_IMG="$(ls -1t "${ROOT}/deploy"/img-ourbox-matchbox-installer-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${INSTALLER_IMG}" && -f "${INSTALLER_IMG}" ]] || die "No installer image found in deploy/"

./tools/flash-installer-media.sh "${INSTALLER_IMG}" "${TARGET_DEV}"

log "Done: boot the Pi from installer media, follow prompts, then remove media and boot NVMe."
