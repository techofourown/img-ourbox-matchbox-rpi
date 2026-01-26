#!/usr/bin/env bash
set -euo pipefail

# pi-gen provides ROOTFS_DIR
: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

# Refuse to build if the airgap artifacts aren’t present
test -x "artifacts/airgap/k3s/k3s"
test -f "artifacts/airgap/k3s/k3s-airgap-images-arm64.tar"
test -f "artifacts/airgap/platform/images/nginx_1.27-alpine.tar"

echo "==> Installing k3s binary"
install -D -m 0755 \
  "artifacts/airgap/k3s/k3s" \
  "${ROOTFS_DIR}/usr/local/bin/k3s"

echo "==> Copying airgap image tars"
install -D -m 0644 \
  "artifacts/airgap/k3s/k3s-airgap-images-arm64.tar" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/k3s/k3s-airgap-images-arm64.tar"

install -D -m 0644 \
  "artifacts/airgap/platform/images/nginx_1.27-alpine.tar" \
  "${ROOTFS_DIR}/opt/ourbox/airgap/platform/images/nginx_1.27-alpine.tar"

echo "==> Installing platform manifests + systemd units + bootstrap script"
cp -a \
  "pigen/stages/stage-ourbox-mini/02-airgap-platform/files/." \
  "${ROOTFS_DIR}/"
