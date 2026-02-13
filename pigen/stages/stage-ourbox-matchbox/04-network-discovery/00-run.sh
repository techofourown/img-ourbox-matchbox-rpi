#!/usr/bin/env bash
set -euo pipefail

: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing mDNS alias service and script"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
chmod 0755 "${ROOTFS_DIR}/usr/local/sbin/ourbox-mdns-aliases"
