#!/usr/bin/env bash
set -euo pipefail

: "${ROOTFS_DIR:?ROOTFS_DIR not set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing MOTD status banner"
cp -a "${SCRIPT_DIR}/files/." "${ROOTFS_DIR}/"
chmod 0755 "${ROOTFS_DIR}/etc/update-motd.d/10-ourbox-status"
