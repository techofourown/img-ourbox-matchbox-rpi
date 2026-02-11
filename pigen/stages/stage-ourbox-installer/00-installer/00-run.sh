#!/usr/bin/env bash
set -euo pipefail

: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${ROOTFS_DIR}/opt/ourbox/installer"

mkdir -p "${INSTALLER_DIR}"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"

payload="$(ls -1t /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz 2>/dev/null | head -n 1 || true)"
[[ -n "${payload}" && -f "${payload}" ]] || {
  echo "ERROR: no payload found matching /ourbox/deploy/img-ourbox-matchbox-rpi-*.img.xz" >&2
  exit 1
}

install -D -m 0644 "${payload}" "${INSTALLER_DIR}/os.img.xz"
sha256="$(sha256sum "${INSTALLER_DIR}/os.img.xz" | awk '{print $1}')"
basename_payload="$(basename "${payload}")"
build_ts="$(date -Is)"
variant="${OURBOX_VARIANT:-dev}"
version="${OURBOX_VERSION:-dev}"

cat > "${INSTALLER_DIR}/manifest.env" <<MANIFEST
PAYLOAD_BASENAME=${basename_payload}
PAYLOAD_SHA256=${sha256}
BUILD_TS=${build_ts}
OURBOX_VARIANT=${variant}
OURBOX_VERSION=${version}
MANIFEST

info_file="${payload%.img.xz}.info"
if [[ -f "${info_file}" ]]; then
  install -D -m 0644 "${info_file}" "${INSTALLER_DIR}/os.info"
fi
