#!/usr/bin/env bash
set -euo pipefail

# pi-gen provides ROOTFS_DIR
: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

AIRGAP="${REPO_ROOT}/artifacts/airgap"

# Refuse to build if the airgap artifacts aren’t present
test -x "${AIRGAP}/k3s/k3s"
test -f "${AIRGAP}/k3s/k3s-airgap-images-arm64.tar"
test -f "${AIRGAP}/platform/images/nginx_1.27-alpine.tar"

echo "==> Installing k3s binary"
install -D -m 0755 \
  "${AIRGAP}/k3s/k3s" \
  "${ROOTFS_DIR}/usr/local/bin/k3s"

echo "==> Copying airgap image tars"
install -D -m 0644 \
  "${AIRGAP}/k3s/k3s-airgap-images-arm64.tar" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/k3s/k3s-airgap-images-arm64.tar"

install -D -m 0644 \
  "${AIRGAP}/platform/images/nginx_1.27-alpine.tar" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/platform/images/nginx_1.27-alpine.tar"

echo "==> Installing platform manifests + systemd units + bootstrap script"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
