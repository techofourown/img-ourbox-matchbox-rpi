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
DEV="${2:-}"

if [[ -z "${IMG}" || -z "${DEV}" ]]; then
  die "Usage: $0 PATH_TO_INSTALLER_IMG_XZ TARGET_DEV"
fi

need_cmd lsblk
need_cmd readlink
need_cmd findmnt
need_cmd wipefs
need_cmd dd
need_cmd blockdev
need_cmd xzcat

[[ -f "${IMG}" ]] || die "installer image not found: ${IMG}"
DEV="$(readlink -f "${DEV}")"
[[ -b "${DEV}" ]] || die "not a block device: ${DEV}"

[[ "$(lsblk -dn -o TYPE "${DEV}")" == "disk" ]] || die "target must be a raw disk: ${DEV}"

root_src="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
root_real="$(readlink -f "${root_src}" 2>/dev/null || echo "${root_src}")"
root_parent="$(lsblk -no PKNAME "${root_real}" 2>/dev/null || true)"
if [[ -n "${root_parent}" ]]; then
  root_real="/dev/${root_parent}"
fi
[[ "${DEV}" != "${root_real}" ]] || die "Refusing to flash root disk backing / (${root_real})"

while read -r name mp; do
  [[ -n "${mp}" ]] || continue
  umount "/dev/${name}" >/dev/null 2>&1 || umount "${mp}" >/dev/null 2>&1 || true
done < <(lsblk -nr -o NAME,MOUNTPOINT "${DEV}" | awk 'NF==2 && $2!="" {print $1, $2}')

if lsblk -nr -o MOUNTPOINT "${DEV}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}" || true
  die "could not unmount all partitions on ${DEV}"
fi

size_bytes="$(blockdev --getsize64 "${DEV}")"
if (( size_bytes < 32000000000 )); then
  die "${DEV} is too small (${size_bytes} bytes). Minimum required: 32000000000 bytes"
fi

lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}" || true

read -r -p "Type FLASH to continue: " ans
[[ "${ans}" == "FLASH" ]] || die "confirmation did not match FLASH"
read -r -p "Type target device path to confirm (${DEV}): " dev_confirm
[[ "${dev_confirm}" == "${DEV}" ]] || die "device confirmation did not match"

if command -v blkdiscard >/dev/null 2>&1; then
  blkdiscard -f "${DEV}" >/dev/null 2>&1 || true
fi
wipefs -a "${DEV}" >/dev/null 2>&1 || true

zero_mib=32
dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" conv=fsync status=progress
total_mib="$((size_bytes / 1024 / 1024))"
if (( total_mib > zero_mib )); then
  seek_mib="$((total_mib - zero_mib))"
  dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" seek="${seek_mib}" conv=fsync status=progress
fi

xzcat "${IMG}" | dd of="${DEV}" bs=4M conv=fsync status=progress
sync
log "Installer media flashed: ${DEV}"
