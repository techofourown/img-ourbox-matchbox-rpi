#!/usr/bin/env bash
# Official installer artifact promotion wrapper.
# Metadata outputs remain channel-neutral candidate-build metadata; release semantics
# live in tags and installer-artifact.promote.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/release/official-artifacts.env"

need_cmd python3

PROMOTION_CONTEXT="${1:?Usage: promote-installer-artifact-official.sh stable|exp-labs}"
DEPLOY_DIR="${DEPLOY_DIR:-${ROOT}/deploy}"
mkdir -p "${DEPLOY_DIR}"

RELEASE_TAG="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
[[ -n "${RELEASE_TAG}" ]] || die "release tag not set (RELEASE_TAG and GITHUB_REF_NAME are both empty)"
CANDIDATE_PROVENANCE_JSON="${CANDIDATE_PROVENANCE_JSON:-}"
[[ -n "${CANDIDATE_PROVENANCE_JSON}" ]] || die "CANDIDATE_PROVENANCE_JSON must point to the candidate provenance bundle"

case "${PROMOTION_CONTEXT}" in
  stable)
    PROMOTE_VERSION="${RELEASE_TAG}"
    TARGET_CHANNEL_TAGS="${OFFICIAL_INSTALLER_STABLE_CHANNELS}"
    ;;
  exp-labs)
    PROMOTE_VERSION="${RELEASE_TAG}"
    TARGET_CHANNEL_TAGS="${OFFICIAL_INSTALLER_EXP_LABS_CHANNELS}"
    ;;
  *)
    die "Unknown promotion context: ${PROMOTION_CONTEXT} (expected: stable|exp-labs)"
    ;;
esac

TARGET_IMMUTABLE_TAG="${PROMOTE_VERSION}-${OURBOX_TARGET}-installer"

python3 "${ROOT}/tools/release-control/release_control.py" promote-installer \
  --provenance "${CANDIDATE_PROVENANCE_JSON}" \
  --release-tag "${RELEASE_TAG}" \
  --promotion-context "${PROMOTION_CONTEXT}" \
  --artifact-repo "${OFFICIAL_INSTALLER_REPO}" \
  --expected-artifact-kind "${OFFICIAL_INSTALLER_ARTIFACT_KIND}" \
  --expected-artifact-type "${OFFICIAL_INSTALLER_ARTIFACT_TYPE}" \
  --expected-target "${OURBOX_TARGET}" \
  --expected-variant "${OURBOX_VARIANT}" \
  --expected-sku "${OURBOX_SKU}" \
  --immutable-tag "${TARGET_IMMUTABLE_TAG}" \
  --channel-tags "${TARGET_CHANNEL_TAGS}" \
  --deploy-dir "${DEPLOY_DIR}"
