#!/usr/bin/env bash
set -euo pipefail

[[ -d "/ourbox/deploy" ]] || { echo "ERROR: /ourbox/deploy is missing" >&2; exit 1; }

target="${OURBOX_TARGET:-rpi}"
payload_glob="/ourbox/deploy/img-ourbox-matchbox-${target,,}-*.img.xz"

shopt -s nullglob
payloads=(${payload_glob})
shopt -u nullglob

[[ "${#payloads[@]}" -gt 0 ]] || {
  echo "ERROR: no target OS payload found at ${payload_glob}" >&2
  exit 1
}
