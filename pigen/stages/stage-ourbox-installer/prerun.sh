#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d "${ROOTFS_DIR}" ]]; then
  copy_previous
fi

[[ -d /ourbox/deploy ]] || { echo "ERROR: /ourbox/deploy not found (is repo mounted at /ourbox?)" >&2; exit 1; }

shopt -s nullglob
payloads=(/ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz)
shopt -u nullglob

(( ${#payloads[@]} > 0 )) || {
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
}
