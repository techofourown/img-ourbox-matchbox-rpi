#!/usr/bin/env bash
set -euo pipefail

log()  { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die()  { log "ERROR: $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Last token handles "sudo nerdctl"
cli_base() { echo "${1##* }"; }

resolve_label() {
  local label="$1"
  local dev=""

  if command -v blkid >/dev/null 2>&1; then
    dev="$(blkid -L "${label}" 2>/dev/null || true)"
    if [[ -n "${dev}" ]]; then
      readlink -f "${dev}"
      return 0
    fi
  fi

  if [[ -e "/dev/disk/by-label/${label}" ]]; then
    readlink -f "/dev/disk/by-label/${label}"
    return 0
  fi

  echo ""
}
