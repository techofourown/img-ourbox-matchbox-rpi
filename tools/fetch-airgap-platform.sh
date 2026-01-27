#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd curl
need_cmd chmod
need_cmd sed

: "${K3S_VERSION:=}"
: "${NGINX_IMAGE:=docker.io/library/nginx:1.27-alpine}"

if [[ -z "${K3S_VERSION}" ]]; then
  if [[ "${RESOLVE_LATEST_K3S:-0}" == "1" ]]; then
    log "K3S_VERSION not set; resolving latest from GitHub releases (dev only)"
    K3S_VERSION="$(
      curl -fsSLI https://github.com/k3s-io/k3s/releases/latest \
        | tr -d '\r' \
        | sed -n 's/^location: .*\/tag\/\(v[^ ]*\)$/\1/ip' \
        | tail -n1
    )"
  else
    die "K3S_VERSION not set. Edit tools/versions.env (recommended) or export K3S_VERSION."
  fi
fi

NGINX_IMAGE="$(canonicalize_image_ref "${NGINX_IMAGE}")"

log "Using K3S_VERSION=${K3S_VERSION}"
log "Using NGINX_IMAGE=${NGINX_IMAGE}"

OUT="artifacts/airgap"
mkdir -p "$OUT/k3s" "$OUT/platform/images"

# Consistent tar name derived from image ref
NGINX_TAR="$(echo "${NGINX_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"

log "Fetch k3s binary (arm64) @ ${K3S_VERSION}"
curl -fsSL \
  -o "$OUT/k3s/k3s" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-arm64"
chmod +x "$OUT/k3s/k3s"

log "Fetch k3s airgap images (arm64) @ ${K3S_VERSION}"
curl -fsSL \
  -o "$OUT/k3s/k3s-airgap-images-arm64.tar" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-arm64.tar"

CLI="$(pick_container_cli)"
log "Using container CLI: ${CLI}"

log "Pull + save demo image (arm64): ${NGINX_IMAGE}"

case "$(cli_base "${CLI}")" in
  nerdctl|docker)
    # shellcheck disable=SC2086
    $CLI pull --platform=linux/arm64 "${NGINX_IMAGE}"
    if [[ "$(cli_base "${CLI}")" = "nerdctl" ]]; then
      # shellcheck disable=SC2086
      $CLI save --platform=linux/arm64 -o "$OUT/platform/images/${NGINX_TAR}" "${NGINX_IMAGE}"
    else
      # shellcheck disable=SC2086
      $CLI save -o "$OUT/platform/images/${NGINX_TAR}" "${NGINX_IMAGE}"
    fi
    ;;
  podman)
    # shellcheck disable=SC2086
    $CLI pull --arch=arm64 --os=linux "${NGINX_IMAGE}"
    # shellcheck disable=SC2086
    $CLI save -o "$OUT/platform/images/${NGINX_TAR}" "${NGINX_IMAGE}"
    ;;
  *)
    die "Unsupported container CLI: ${CLI}"
    ;;
esac

log "Writing airgap manifest"
cat > "$OUT/manifest.env" <<EOF_MANIFEST
K3S_VERSION=${K3S_VERSION}
NGINX_IMAGE=${NGINX_IMAGE}
EOF_MANIFEST

log "Artifacts created:"
ls -lah "$OUT/k3s" "$OUT/platform/images" "$OUT/manifest.env"
