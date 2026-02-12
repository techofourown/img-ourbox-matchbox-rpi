#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

if [[ ${EUID} -ne 0 ]]; then
  need_cmd sudo
  exec sudo -E -- "$0" "$@"
fi

need_cmd losetup
need_cmd awk
need_cmd grep
if command -v modprobe >/dev/null 2>&1; then
  # Ensure loop module exists (no-op if built-in)
  modprobe loop >/dev/null 2>&1 || true
fi

log "Preflight: cleaning stale loop devices (lost/deleted)"
bad="$(
  losetup -a 2>/dev/null \
    | awk '/\((deleted|lost)\)/{sub(/:.*/,"",$1); print $1}' \
    | sort -u
)"

if [[ -n "${bad}" ]]; then
  while read -r dev; do
    [[ -n "${dev}" ]] || continue
    log "Detaching stale loop: ${dev}"
    losetup -d "${dev}" >/dev/null 2>&1 || true
  done <<< "${bad}"
fi

if losetup -a 2>/dev/null | grep -qE '\((deleted|lost)\)'; then
  die "Loop device state is unhealthy (lost/deleted loops remain). Reboot the build host to reset kernel loop state."
fi

log "Preflight: loop devices OK"
