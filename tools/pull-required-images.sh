#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/registry.sh"

cli="$(pick_container_cli)"

pull_and_tag() {
  local src="$1" dst="$2"
  echo ">> Pull: $src"
  # shellcheck disable=SC2086
  $cli pull "$src"
  echo ">> Tag:  $src -> $dst"
  # shellcheck disable=SC2086
  $cli tag "$src" "$dst"
}

# pi-gen Dockerfile build arg uses "debian:trixie"
pull_and_tag "$(imgref mirror/debian trixie)" "debian:trixie"

# Optional convenience tag (not strictly needed for our buildkitd approach)
pull_and_tag "$(imgref mirror/buildkit v0.23.2)" "moby/buildkit:v0.23.2"
