#!/usr/bin/env bash
# Official OS artifact promotion wrapper.
# Metadata outputs remain channel-neutral candidate-build metadata; release semantics
# live in tags, catalog rows, and os-artifact.promote.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/release/official-artifacts.env"

need_cmd python3

PROMOTION_CONTEXT="${1:?Usage: promote-os-artifact-official.sh stable|exp-labs}"
DEPLOY_DIR="${DEPLOY_DIR:-${ROOT}/deploy}"
mkdir -p "${DEPLOY_DIR}"

RELEASE_TAG="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
[[ -n "${RELEASE_TAG}" ]] || die "release tag not set (RELEASE_TAG and GITHUB_REF_NAME are both empty)"
CANDIDATE_PROVENANCE_JSON="${CANDIDATE_PROVENANCE_JSON:-}"
[[ -n "${CANDIDATE_PROVENANCE_JSON}" ]] || die "CANDIDATE_PROVENANCE_JSON must point to the candidate provenance bundle"

case "${PROMOTION_CONTEXT}" in
  stable)
    PROMOTE_VERSION="${RELEASE_TAG}"
    TARGET_CHANNEL_TAGS="${OFFICIAL_OS_STABLE_CHANNELS}"
    ;;
  exp-labs)
    PROMOTE_VERSION="${RELEASE_TAG}"
    TARGET_CHANNEL_TAGS="${OFFICIAL_OS_EXP_LABS_CHANNELS}"
    ;;
  *)
    die "Unknown promotion context: ${PROMOTION_CONTEXT} (expected: stable|exp-labs)"
    ;;
esac

TARGET_IMMUTABLE_TAG="${PROMOTE_VERSION}-${OURBOX_TARGET}"

python3 "${ROOT}/tools/release-control/release_control.py" promote-os \
  --provenance "${CANDIDATE_PROVENANCE_JSON}" \
  --release-tag "${RELEASE_TAG}" \
  --promotion-context "${PROMOTION_CONTEXT}" \
  --artifact-repo "${OFFICIAL_OS_REPO}" \
  --expected-artifact-kind "${OFFICIAL_OS_ARTIFACT_KIND}" \
  --expected-artifact-type "${OFFICIAL_OS_ARTIFACT_TYPE}" \
  --expected-target "${OURBOX_TARGET}" \
  --expected-variant "${OURBOX_VARIANT}" \
  --expected-sku "${OURBOX_SKU}" \
  --immutable-tag "${TARGET_IMMUTABLE_TAG}" \
  --channel-tags "${TARGET_CHANNEL_TAGS}" \
  --catalog-tag "${OFFICIAL_OS_CATALOG_TAG}" \
  --catalog-artifact-type "${OFFICIAL_OS_CATALOG_ARTIFACT_TYPE}" \
  --channel-mode "${OFFICIAL_OS_CATALOG_CHANNEL_MODE}" \
  --sha-column "${OFFICIAL_OS_CATALOG_SHA_COLUMN}" \
  --deploy-dir "${DEPLOY_DIR}"
