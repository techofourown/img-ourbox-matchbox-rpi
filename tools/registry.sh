#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f "$(dirname "$0")/registry.env" ] && source "$(dirname "$0")/registry.env"

: "${REGISTRY:=registry.benac.dev}"
: "${REGISTRY_NAMESPACE:=ourbox}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }

pick_container_cli() {
  if [ -n "${DOCKER:-}" ]; then
    echo "$DOCKER"
    return 0
  fi
  if command -v nerdctl >/dev/null 2>&1; then echo nerdctl; return 0; fi
  if command -v docker   >/dev/null 2>&1; then echo docker;   return 0; fi
  if command -v podman   >/dev/null 2>&1; then echo podman;   return 0; fi
  echo "No container CLI found (need nerdctl, docker, or podman)." >&2
  exit 1
}

imgref() {
  # Usage: imgref <name> <tag>
  local name="$1" tag="$2"
  echo "${REGISTRY}/${REGISTRY_NAMESPACE}/${name}:${tag}"
}

mirror_image() {
  # Usage: mirror_image <src> <dst>
  local src="$1" dst="$2"
  local cli; cli="$(pick_container_cli)"
  echo ">> Pull: $src"
  "$cli" pull "$src"
  echo ">> Tag:  $src -> $dst"
  "$cli" tag "$src" "$dst"
  echo ">> Push: $dst"
  "$cli" push "$dst"
}
