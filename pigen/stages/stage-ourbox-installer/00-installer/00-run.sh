#!/usr/bin/env bash
set -euo pipefail

: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"

install -d -m 0755 "${ROOTFS_DIR}/opt/ourbox/installer"

target="${OURBOX_TARGET:-rpi}"
payload_glob="/ourbox/deploy/img-ourbox-matchbox-${target,,}-*.img.xz"

payload="$(ls -1t ${payload_glob} 2>/dev/null | head -n 1 || true)"
[[ -n "${payload}" && -f "${payload}" ]] || {
  echo "ERROR: no target OS payload found at ${payload_glob}" >&2
  exit 1
}

payload_base="$(basename "${payload}")"
install -m 0644 "${payload}" "${ROOTFS_DIR}/opt/ourbox/installer/os.img.xz"
sha256="$(sha256sum "${ROOTFS_DIR}/opt/ourbox/installer/os.img.xz" | awk '{print $1}')"
build_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${ROOTFS_DIR}/opt/ourbox/installer/manifest.env" <<MANIFEST
PAYLOAD_BASENAME=${payload_base}
PAYLOAD_SHA256=${sha256}
BUILD_TS=${build_ts}
OURBOX_VARIANT=${OURBOX_VARIANT:-dev}
OURBOX_VERSION=${OURBOX_VERSION:-dev}
MANIFEST

info_src="${payload%.img.xz}.info"
if [[ -f "${info_src}" ]]; then
  install -m 0644 "${info_src}" "${ROOTFS_DIR}/opt/ourbox/installer/os.info"
fi
