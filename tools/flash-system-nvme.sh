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
SYS_DISK="${2:-}"
DATA_PART="/dev/disk/by-label/OURBOX_DATA"

if [ -z "${IMG}" ] || [ -z "${SYS_DISK}" ]; then
  die "Usage: $0 PATH_TO_OS_IMG_XZ SYS_DISK"
fi

case "${SYS_DISK}" in
  /dev/disk/by-id/*) ;;
  /dev/nvme*) ;;
  *) die "SYS_DISK must be /dev/disk/by-id/... or /dev/nvme... (got: ${SYS_DISK})" ;;
esac

need_cmd xz
need_cmd xzcat
need_cmd dd
need_cmd lsblk
need_cmd readlink
need_cmd partprobe

if [ ! -e "${DATA_PART}" ]; then
  die "DATA disk not found: ${DATA_PART}"
fi

if [ ! -f "${IMG}" ]; then
  die "Image not found: ${IMG}"
fi

log "Verifying image integrity: ${IMG}"
xz -t "${IMG}"

DATA_DEV="$(readlink -f "${DATA_PART}")"
DATA_DISK="/dev/$(lsblk -no PKNAME "${DATA_DEV}")"
SYS_DEV="$(readlink -f "${SYS_DISK}")"

# Refuse if anything on SYSTEM disk is mounted (safety)
if lsblk -nr -o MOUNTPOINT "${SYS_DEV}" | grep -qE '\S'; then
  die "SYSTEM disk has mounted partitions. Unmount them and retry."
fi

if [[ "${SYS_DISK}" != /dev/disk/by-id/* ]]; then
  log "WARNING: SYS_DISK is not a by-id path. by-id is preferred for safety."
fi

if [ "$(lsblk -no TYPE "${SYS_DEV}")" != "disk" ]; then
  die "SYS_DISK must resolve to a raw disk (got: ${SYS_DEV})"
fi

log "IMG=${IMG}"
log "DATA_PART=${DATA_PART} -> ${DATA_DEV} (disk ${DATA_DISK})"
log "SYS_DISK=${SYS_DISK} -> ${SYS_DEV}"

echo
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK}"
echo
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${SYS_DEV}"
echo

if [ "${SYS_DEV}" = "${DATA_DISK}" ]; then
  die "SYS_DEV resolves to DATA disk (${DATA_DISK}). Refusing."
fi

read -r -p "Type FLASH (all caps) to erase and flash ${SYS_DEV}: " ans
[ "${ans}" = "FLASH" ]

log "Flashing ${IMG} -> ${SYS_DEV}"
xzcat "${IMG}" | dd of="${SYS_DEV}" bs=4M conv=fsync status=progress
sync

log "Refreshing partition table"
partprobe "${SYS_DEV}" || true
lsblk -f "${SYS_DEV}"
