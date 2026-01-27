#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f "$(dirname "$0")/registry.env" ] && source "$(dirname "$0")/registry.env"
# shellcheck disable=SC1091
[ -f "$(dirname "$0")/versions.env" ] && source "$(dirname "$0")/versions.env"

: "${REGISTRY:=registry.benac.dev}"
: "${REGISTRY_NAMESPACE:=ourbox}"
: "${BUILDKIT_VERSION:=v0.23.2}"

if ! declare -F need_cmd >/dev/null 2>&1; then
  need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
fi

pick_container_cli() {
  # Honor explicit override.
  if [ -n "${DOCKER:-}" ]; then
    echo "$DOCKER"
    return 0
  fi

  # Prefer Podman. Default to rootful when not root.
  if command -v podman >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      echo podman
    else
      if command -v sudo >/dev/null 2>&1; then
        echo "sudo podman"
      else
        echo podman
      fi
    fi
    return 0
  fi

  # Fallbacks (rootful defaults if not root).
  if command -v docker >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then echo docker; else echo "sudo docker"; fi
    return 0
  fi

  if command -v nerdctl >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then echo nerdctl; else echo "sudo nerdctl"; fi
    return 0
  fi

  echo "No container CLI found (need podman, docker, or nerdctl)." >&2
  exit 1
}

imgref() {
  # Usage: imgref name tag
  local name="$1" tag="$2"
  echo "${REGISTRY}/${REGISTRY_NAMESPACE}/${name}:${tag}"
}

canonicalize_image_ref() {
  local ref="$1"
  local first="${ref%%/*}"

  # Already qualified if first component looks like a registry (contains '.' or ':' or is localhost)
  if [[ "${first}" == *"."* || "${first}" == *":"* || "${first}" == "localhost" ]]; then
    echo "${ref}"
    return 0
  fi

  # Unqualified. If it already has a namespace (a/b:tag), assume docker.io/<namespace>/...
  if [[ "${ref}" == */* ]]; then
    echo "docker.io/${ref}"
    return 0
  fi

  # Bare image (nginx:tag) -> docker.io/library/<image>:tag
  echo "docker.io/library/${ref}"
}

mirror_image() {
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
  # Only needed for nerdctl builds (kept for compatibility).
  local cli; cli="$(pick_container_cli)"
  local cli_base="${cli##* }"
  if [ "$cli_base" != "nerdctl" ]; then
    return 0
  fi

  local name="${BUILDKITD_NAME:-buildkitd}"
  local image="${BUILDKITD_IMAGE:-$(imgref mirror/buildkit "${BUILDKIT_VERSION}")}"

  mkdir -p /run/buildkit /run/buildkit-default

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
