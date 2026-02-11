#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [[ ${EUID} -ne 0 ]]; then
  log "Re-executing with sudo..."
  exec sudo -E -- "$0" "$@"
fi

IMG="${1:-}"
TARGET_DEV_INPUT="${2:-}"

if [[ -z "${IMG}" || -z "${TARGET_DEV_INPUT}" ]]; then
  die "Usage: $0 PATH_TO_INSTALLER_IMG_XZ TARGET_DEV"
fi

need_cmd xz
need_cmd xzcat
need_cmd dd
need_cmd readlink
need_cmd lsblk
need_cmd findmnt
need_cmd blockdev
need_cmd wipefs
need_cmd umount
need_cmd sync

[[ -f "${IMG}" ]] || die "Image not found: ${IMG}"
xz -t "${IMG}"

DEV="$(readlink -f "${TARGET_DEV_INPUT}")"
[[ -b "${DEV}" ]] || die "Target is not a block device: ${DEV}"

dev_type="$(lsblk -dn -o TYPE "${DEV}" 2>/dev/null | tr -d '[:space:]')"
[[ "${dev_type}" == "disk" ]] || die "TARGET_DEV must resolve to a raw disk (got ${DEV}, type=${dev_type:-unknown})"

root_src="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
root_real="$(readlink -f "${root_src}" 2>/dev/null || echo "${root_src}")"
root_parent="$(lsblk -no PKNAME "${root_real}" 2>/dev/null || true)"
if [[ -n "${root_parent}" ]]; then
  root_disk="/dev/${root_parent}"
else
  root_disk="${root_real}"
fi

[[ "${DEV}" != "${root_disk}" ]] || die "Refusing to flash disk backing / (${root_disk})"

while read -r name mp; do
  [[ -n "${mp}" ]] || continue
  umount "/dev/${name}" >/dev/null 2>&1 || umount "${mp}" >/dev/null 2>&1 || true
done < <(lsblk -nr -o NAME,MOUNTPOINT "${DEV}" | awk 'NF==2 && $2!="" {print $1, $2}')

if lsblk -nr -o MOUNTPOINT "${DEV}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
  lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}" || true
  die "Partitions on ${DEV} are still mounted"
fi

size_bytes="$(blockdev --getsize64 "${DEV}")"
(( size_bytes >= 32000000000 )) || die "Target device too small (${size_bytes} bytes). Minimum is 32000000000 bytes"

lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DEV}" || true

prompt=""
read -r -p "Type FLASH to write installer media to ${DEV}: " prompt
[[ "${prompt}" == "FLASH" ]] || die "confirmation did not match"
read -r -p "Type device path exactly (${DEV}): " prompt
[[ "${prompt}" == "${DEV}" ]] || die "device confirmation did not match"

if command -v blkdiscard >/dev/null 2>&1; then
  log "blkdiscard (best-effort): ${DEV}"
  blkdiscard -f "${DEV}" >/dev/null 2>&1 || true
fi

log "wipefs (best-effort): ${DEV}"
wipefs -a "${DEV}" >/dev/null 2>&1 || true

zero_mib=32
log "Zeroing first ${zero_mib}MiB of ${DEV}"
dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" conv=fsync status=progress

total_mib="$((size_bytes / 1024 / 1024))"
if (( total_mib > zero_mib )); then
  seek_mib="$((total_mib - zero_mib))"
  log "Zeroing last ${zero_mib}MiB of ${DEV}"
  dd if=/dev/zero of="${DEV}" bs=1M count="${zero_mib}" seek="${seek_mib}" conv=fsync status=progress
fi
sync

log "Flashing installer image ${IMG} -> ${DEV}"
xzcat "${IMG}" | dd of="${DEV}" bs=4M conv=fsync status=progress
sync

log "Installer media flash complete"
