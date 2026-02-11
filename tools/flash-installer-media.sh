#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [ "${EUID}" -ne 0 ]; then
  log "Re-executing with sudo..."
  exec sudo -E -- "$0" "$@"
fi

IMG="${1:-}"
TARGET_DEV="${2:-}"

if [ -z "${IMG}" ] || [ -z "${TARGET_DEV}" ]; then
  die "Usage: $0 PATH_TO_INSTALLER_IMG_XZ TARGET_DEV"
fi

need_cmd xz
need_cmd xzcat
need_cmd dd
need_cmd lsblk
need_cmd readlink
need_cmd findmnt
need_cmd awk
need_cmd umount
need_cmd wipefs
need_cmd blockdev
need_cmd sync

[ -f "${IMG}" ] || die "Image not found: ${IMG}"

DEV="$(readlink -f "${TARGET_DEV}")"
[ -b "${DEV}" ] || die "Target is not a block device: ${TARGET_DEV}"

DEV_TYPE="$(lsblk -dn -o TYPE "${DEV}" 2>/dev/null | head -n1 | tr -d '[:space:]')"
[[ "${DEV_TYPE}" == "disk" ]] || die "TARGET_DEV must resolve to a raw disk (got type=${DEV_TYPE:-unknown})"

root_src="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
root_real="$(readlink -f "${root_src}" 2>/dev/null || echo "${root_src}")"
root_parent="$(lsblk -no PKNAME "${root_real}" 2>/dev/null || true)"
if [[ -n "${root_parent}" ]]; then
  root_real="/dev/${root_parent}"
fi
[[ "${DEV}" != "${root_real}" ]] || die "Refusing to flash device backing / (${DEV})"

while read -r part mp; do
  [[ -n "${mp}" ]] || continue
  umount "/dev/${part}" >/dev/null 2>&1 || umount "${mp}" >/dev/null 2>&1 || true
done < <(lsblk -nr -o NAME,MOUNTPOINT "${DEV}" | awk 'NF==2 && $2!="" {print $1, $2}')

if lsblk -nr -o MOUNTPOINT "${DEV}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}"
  die "Could not unmount all partitions on ${DEV}"
fi

size_bytes="$(blockdev --getsize64 "${DEV}")"
(( size_bytes >= 32000000000 )) || die "Target device is too small (${size_bytes} bytes); need at least 32000000000 bytes"

log "Verifying installer image integrity: ${IMG}"
xz -t "${IMG}"

echo
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}"
echo

read -r -p "Type FLASH to erase and flash ${DEV}: " ans1
[[ "${ans1}" == "FLASH" ]] || die "confirmation did not match FLASH"
read -r -p "Type device path exactly (${DEV}) to confirm: " ans2
[[ "${ans2}" == "${DEV}" ]] || die "device confirmation mismatch"

if command -v blkdiscard >/dev/null 2>&1; then
  blkdiscard -f "${DEV}" >/dev/null 2>&1 || true
fi
wipefs -a "${DEV}" >/dev/null 2>&1 || true

zero_mib="${ZERO_MIB:-32}"
dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" conv=fsync status=progress

total_mib="$((size_bytes / 1024 / 1024))"
if (( total_mib > zero_mib )); then
  seek_mib="$((total_mib - zero_mib))"
  dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" seek="${seek_mib}" conv=fsync status=progress
fi

xzcat "${IMG}" | dd of="${DEV}" bs=4M conv=fsync status=progress
sync

log "Installer media flash complete: ${DEV}"
