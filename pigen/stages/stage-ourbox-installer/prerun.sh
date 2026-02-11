#!/usr/bin/env bash
set -euo pipefail

if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi

if [ ! -d /ourbox/deploy ]; then
  echo "ERROR: missing /ourbox/deploy mount (expected repo mounted at /ourbox)" >&2
  exit 1
fi

shopt -s nullglob
payloads=(/ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz)
shopt -u nullglob

if [ "${#payloads[@]}" -lt 1 ]; then
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
fi
