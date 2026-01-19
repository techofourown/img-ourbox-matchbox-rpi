#!/bin/bash -e

install -d -m 0755 "${ROOTFS_DIR}/etc/ourbox"

# Try to capture the recipe git hash (the parent repo), if present in the container mount.
OURBOX_RECIPE_GIT_HASH="$(git -C /ourbox rev-parse HEAD 2>/dev/null || echo "unknown")"

cat > "${ROOTFS_DIR}/etc/ourbox/release" <<EOT
OURBOX_PRODUCT=${OURBOX_PRODUCT}
OURBOX_DEVICE=${OURBOX_DEVICE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_SKU=${OURBOX_SKU}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_RECIPE_GIT_HASH=${OURBOX_RECIPE_GIT_HASH}
EOT

chmod 0644 "${ROOTFS_DIR}/etc/ourbox/release"
