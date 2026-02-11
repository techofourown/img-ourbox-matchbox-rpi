#!/usr/bin/env bash
set -euo pipefail

[[ -d "/ourbox/deploy" ]] || { echo "ERROR: /ourbox/deploy is missing" >&2; exit 1; }

shopt -s nullglob
payloads=(/ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz)
shopt -u nullglob

[[ "${#payloads[@]}" -gt 0 ]] || {
  echo "ERROR: no target OS payload found at /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
}
