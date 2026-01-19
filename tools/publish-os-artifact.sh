#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/registry.sh"

CLI="$(pick_container_cli)"

DEPLOY_DIR="${1:-deploy}"

IMG_XZ="$(ls -1 "${DEPLOY_DIR}"/img-*.img.xz | head -n 1)"
if [ -z "${IMG_XZ}" ] || [ ! -f "${IMG_XZ}" ]; then
  echo "No deploy/img-*.img.xz found. Did the build finish and deploy get copied out?" >&2
  exit 1
fi

BASE="$(basename "${IMG_XZ}" .img.xz)"
INFO="${DEPLOY_DIR}/${BASE}.info"
BLOG="${DEPLOY_DIR}/build.log"

# Where it will live in the registry
# Example:
#   registry.benac.dev/ourbox/os:img-ourbox-mini-rpi-too-obx-mini-01-dev-dev
IMAGE="$(imgref os "${BASE}")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "${IMG_XZ}" "${tmp}/os.img.xz"
[ -f "${INFO}" ] && cp "${INFO}" "${tmp}/os.info" || true
[ -f "${BLOG}" ] && cp "${BLOG}" "${tmp}/build.log" || true

cat > "${tmp}/Dockerfile" <<'DOCKERFILE'
FROM scratch
ADD os.img.xz /artifact/os.img.xz
ADD os.info   /artifact/os.info
ADD build.log /artifact/build.log
DOCKERFILE

# If optional files were missing, Docker will fail on ADD; so remove those ADD lines dynamically.
if [ ! -f "${tmp}/os.info" ]; then
  sed -i '/ADD os.info/d' "${tmp}/Dockerfile"
fi
if [ ! -f "${tmp}/build.log" ]; then
  sed -i '/ADD build.log/d' "${tmp}/Dockerfile"
fi

echo ">> Building OCI artifact image: ${IMAGE}"
"$CLI" build -t "${IMAGE}" "${tmp}"

echo ">> Pushing: ${IMAGE}"
"$CLI" push "${IMAGE}"

echo
echo "DONE:"
echo "  ${IMAGE}"
