#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/registry.sh"

# Add anything you want to keep local
mirror_image "docker.io/library/debian:trixie" "$(imgref mirror/debian trixie)"
mirror_image "docker.io/moby/buildkit:v0.23.2" "$(imgref mirror/buildkit v0.23.2)"
