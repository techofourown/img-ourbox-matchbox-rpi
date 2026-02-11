#!/usr/bin/env bash
set -euo pipefail

[ -d "/ourbox/deploy" ] || { echo "ERROR: missing /ourbox/deploy mount" >&2; exit 1; }

shopt -s nullglob
payloads=(/ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz)
shopt -u nullglob

[ "${#payloads[@]}" -gt 0 ] || {
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
}

if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi
