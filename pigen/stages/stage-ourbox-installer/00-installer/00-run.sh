#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 "${ROOTFS_DIR}/opt/ourbox/installer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "${SCRIPT_DIR}/files" ]; then
  cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
fi

shopt -s nullglob
payloads=(/ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz)
shopt -u nullglob

if [ "${#payloads[@]}" -lt 1 ]; then
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
fi

latest_payload="$(ls -1t /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz | head -n 1)"
payload_basename="$(basename "${latest_payload}")"

install -m 0644 "${latest_payload}" "${ROOTFS_DIR}/opt/ourbox/installer/os.img.xz"

payload_sha256="$(sha256sum "${ROOTFS_DIR}/opt/ourbox/installer/os.img.xz" | awk '{print $1}')"
build_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${ROOTFS_DIR}/opt/ourbox/installer/manifest.env" <<MANIFEST
PAYLOAD_BASENAME=${payload_basename}
PAYLOAD_SHA256=${payload_sha256}
BUILD_TS=${build_ts}
OURBOX_VARIANT=${OURBOX_VARIANT:-dev}
OURBOX_VERSION=${OURBOX_VERSION:-dev}
MANIFEST
chmod 0644 "${ROOTFS_DIR}/opt/ourbox/installer/manifest.env"

payload_info="${latest_payload%.img.xz}.info"
if [ -f "${payload_info}" ]; then
  install -m 0644 "${payload_info}" "${ROOTFS_DIR}/opt/ourbox/installer/os.info"
fi
