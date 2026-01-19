#!/bin/bash -e

# OurBox data mountpoint
install -d -m 0755 "${ROOTFS_DIR}/var/lib/ourbox"

# Mount by LABEL to avoid nvme0/nvme1 ordering issues
FSTAB_LINE='LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2'

if ! grep -qF 'LABEL=OURBOX_DATA /var/lib/ourbox' "${ROOTFS_DIR}/etc/fstab"; then
  echo "${FSTAB_LINE}" >> "${ROOTFS_DIR}/etc/fstab"
fi
