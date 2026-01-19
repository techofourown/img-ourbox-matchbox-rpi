#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f "$(dirname "$0")/registry.env" ] && source "$(dirname "$0")/registry.env"

: "${REGISTRY:=registry.benac.dev}"
: "${REGISTRY_NAMESPACE:=ourbox}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }

pick_container_cli() {
  # If caller sets DOCKER, honor it (can be "nerdctl" or "sudo nerdctl").
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
  # shellcheck disable=SC2086
  $cli pull "$src"

  echo ">> Tag:  $src -> $dst"
  # shellcheck disable=SC2086
  $cli tag "$src" "$dst"

  echo ">> Push: $dst"
  # shellcheck disable=SC2086
  $cli push "$dst"
}

ensure_buildkitd() {
  # For nerdctl builds, ensure a buildkitd is running and its socket is mounted on host.
  # For docker/podman, do nothing (they don't need our external buildkitd).
  local cli; cli="$(pick_container_cli)"

  # Get the "actual" binary name (last token handles "sudo nerdctl")
  local cli_base="${cli##* }"
  if [ "$cli_base" != "nerdctl" ]; then
    return 0
  fi

  local name="${BUILDKITD_NAME:-buildkitd}"
  local image="${BUILDKITD_IMAGE:-$(imgref mirror/buildkit v0.23.2)}"

  mkdir -p /run/buildkit /run/buildkit-default

  # If it's already running AND sockets exist, keep it.
  if \
    # shellcheck disable=SC2086
    $cli ps 2>/dev/null | awk 'NR>1{print $NF}' | grep -qx "${name}" \
    && [ -S /run/buildkit/buildkitd.sock ] \
    && [ -S /run/buildkit-default/buildkitd.sock ] \
  ; then
    return 0
  fi

  echo ">> (re)starting buildkitd: ${name} (${image})"
  # shellcheck disable=SC2086
  $cli rm -f "${name}" >/dev/null 2>&1 || true

  # NOTE: we keep this identical to the known-working setup:
  # - bind-mount sockets to host
  # - expose both /run/buildkit and /run/buildkit-default
  # - oci worker is fine; nerdctl will still work
  # shellcheck disable=SC2086
  $cli run -d \
    --name "${name}" \
    --privileged \
    --restart=always \
    -v /run/buildkit:/run/buildkit \
    -v /run/buildkit-default:/run/buildkit-default \
    "${image}" \
    --addr unix:///run/buildkit/buildkitd.sock \
    --addr unix:///run/buildkit-default/buildkitd.sock >/dev/null

  if ! [ -S /run/buildkit/buildkitd.sock ] || ! [ -S /run/buildkit-default/buildkitd.sock ]; then
    echo "ERROR: buildkitd started but socket(s) not present." >&2
    echo "Check: $cli logs --tail=80 ${name}" >&2
    return 1
  fi
}
