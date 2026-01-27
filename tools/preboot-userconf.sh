#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [ "${EUID}" -ne 0 ]; then
  log "Re-executing with sudo..."
  exec sudo -E -- "$0" "$@"
fi

SYS_DEV_INPUT="${1:-}"
NEW_USER="${2:-}"

if [ -z "${SYS_DEV_INPUT}" ] || [ -z "${NEW_USER}" ]; then
  die "Usage: $0 SYS_DEV NEW_USER"
fi

SYS_DEV="$(readlink -f "${SYS_DEV_INPUT}")"
BOOT_PART="${SYS_DEV}p1"
MOUNT_POINT="/mnt/ourbox-boot"

need_cmd openssl
need_cmd mount
need_cmd umount
need_cmd sync

mkdir -p "${MOUNT_POINT}"

log "Mounting ${BOOT_PART} at ${MOUNT_POINT}"
mount "${BOOT_PART}" "${MOUNT_POINT}"

log "Generating password hash for ${NEW_USER}"
HASH="$(openssl passwd -6)"

echo "${NEW_USER}:${HASH}" > "${MOUNT_POINT}/userconf.txt"

sync
umount "${MOUNT_POINT}"

log "Wrote userconf.txt to ${BOOT_PART}"
log "Next: remove SD / set boot order / reboot"
