#!/usr/bin/env bash
set -euo pipefail

# pi-gen provides ROOTFS_DIR
: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

AIRGAP="${REPO_ROOT}/artifacts/airgap"

# Pull the exact versions used when creating the airgap artifacts.
# (This keeps the stage resilient to tar naming changes.)
if [[ -f "${AIRGAP}/manifest.env" ]]; then
  # shellcheck disable=SC1090
  source "${AIRGAP}/manifest.env"
fi

: "${NGINX_IMAGE:=docker.io/library/nginx:1.27-alpine}"
NGINX_TAR="$(echo "${NGINX_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"

# Refuse to build if the airgap artifacts aren’t present
test -x "${AIRGAP}/k3s/k3s" || { echo "ERROR: missing ${AIRGAP}/k3s/k3s" >&2; exit 1; }
test -f "${AIRGAP}/k3s/k3s-airgap-images-arm64.tar" || { echo "ERROR: missing ${AIRGAP}/k3s/k3s-airgap-images-arm64.tar" >&2; exit 1; }
test -f "${AIRGAP}/platform/images/${NGINX_TAR}" || {
  echo "ERROR: missing ${AIRGAP}/platform/images/${NGINX_TAR}" >&2
  echo "Found in ${AIRGAP}/platform/images:" >&2
  ls -lah "${AIRGAP}/platform/images" >&2 || true
  exit 1
}

echo "==> Installing k3s binary"
install -D -m 0755 \
  "${AIRGAP}/k3s/k3s" \
  "${ROOTFS_DIR}/usr/local/bin/k3s"

echo "==> Copying airgap image tars"
install -D -m 0644 \
  "${AIRGAP}/k3s/k3s-airgap-images-arm64.tar" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/k3s/k3s-airgap-images-arm64.tar"

install -D -m 0644 \
  "${AIRGAP}/platform/images/${NGINX_TAR}" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/platform/images/${NGINX_TAR}"

echo "==> Installing platform manifests + systemd units + bootstrap script"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
