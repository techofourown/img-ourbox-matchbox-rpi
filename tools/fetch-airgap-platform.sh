#!/usr/bin/env bash
set -euo pipefail

# Pin this. Change only deliberately.
K3S_VERSION="${K3S_VERSION:-vX.Y.Z+k3s1}"

OUT="artifacts/airgap"
mkdir -p "$OUT/k3s" "$OUT/platform/images"

echo "==> Fetch k3s binary (arm64) @ ${K3S_VERSION}"
curl -fsSL \
  -o "$OUT/k3s/k3s" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-arm64"
chmod +x "$OUT/k3s/k3s"

echo "==> Fetch k3s airgap images (arm64) @ ${K3S_VERSION}"
curl -fsSL \
  -o "$OUT/k3s/k3s-airgap-images-arm64.tar" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-arm64.tar"

# Use your existing container CLI detection if you want;
# for now, pick one and be consistent:
DOCKER="${DOCKER:-docker}"

echo "==> Pull + save demo image (arm64): nginx:1.27-alpine"
$DOCKER pull --platform=linux/arm64 nginx:1.27-alpine
$DOCKER save -o "$OUT/platform/images/nginx_1.27-alpine.tar" nginx:1.27-alpine

echo "==> Done. Artifacts in: $OUT"
