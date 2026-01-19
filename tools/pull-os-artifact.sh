#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/registry.sh"

CLI="$(pick_container_cli)"

IMAGE="${1:?Usage: $0 <registry-image-ref> [outdir]}"
OUTDIR="${2:-deploy-from-registry}"

# Make sure we can pull
echo ">> Pull: ${IMAGE}"
# shellcheck disable=SC2086
$CLI pull "${IMAGE}"

tmp="ourbox_os_artifact_$$"
# clean any old
# shellcheck disable=SC2086
$CLI rm -f "${tmp}" >/dev/null 2>&1 || true

# Scratch image may have no CMD; provide a dummy command so create always succeeds.
echo ">> Create temp container: ${tmp}"
# shellcheck disable=SC2086
$CLI create --name "${tmp}" "${IMAGE}" /bin/true >/dev/null

mkdir -p "${OUTDIR}"

echo ">> Extracting /artifact -> ${OUTDIR}"
# shellcheck disable=SC2086
$CLI cp "${tmp}:/artifact/." "${OUTDIR}/"

# cleanup
# shellcheck disable=SC2086
$CLI rm -f "${tmp}" >/dev/null

echo "DONE: extracted artifact files:"
ls -lah "${OUTDIR}"
