#!/usr/bin/env bash
set -euo pipefail

: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

INSTALLER_DIR="${ROOTFS_DIR}/opt/ourbox/installer"
mkdir -p "${INSTALLER_DIR}"

PAYLOAD="$(ls -1t /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[ -n "${PAYLOAD}" ] || {
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
}

cp -f "${PAYLOAD}" "${INSTALLER_DIR}/os.img.xz"
PAYLOAD_SHA256="$(sha256sum "${INSTALLER_DIR}/os.img.xz" | awk '{print $1}')"
PAYLOAD_BASENAME="$(basename "${PAYLOAD}")"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OURBOX_VARIANT_VAL="${OURBOX_VARIANT:-dev}"
OURBOX_VERSION_VAL="${OURBOX_VERSION:-dev}"

cat > "${INSTALLER_DIR}/manifest.env" <<MANIFEST
PAYLOAD_BASENAME=${PAYLOAD_BASENAME}
PAYLOAD_SHA256=${PAYLOAD_SHA256}
BUILD_TS=${BUILD_TS}
OURBOX_VARIANT=${OURBOX_VARIANT_VAL}
OURBOX_VERSION=${OURBOX_VERSION_VAL}
MANIFEST

INFO_SRC="${PAYLOAD%.img.xz}.info"
if [ -f "${INFO_SRC}" ]; then
  cp -f "${INFO_SRC}" "${INSTALLER_DIR}/os.info"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
