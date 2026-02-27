#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_FILE="${ROOT}/contracts/platform-contract.ref"

[[ -f "${REF_FILE}" ]] || { echo "Missing ${REF_FILE}" >&2; exit 1; }
REF="$(cat "${REF_FILE}")"

command -v oras >/dev/null 2>&1 || {
  echo "oras is required. Run ./tools/bootstrap-host.sh or install ORAS v${ORAS_VERSION:-1.3.0}." >&2
  exit 1
}

OUT_BASE="${ROOT}/artifacts/platform-contract"
PULL_DIR="${OUT_BASE}/pull"
EXTRACT_DIR="${OUT_BASE}/extracted"
META_DIR="${OUT_BASE}/meta"

rm -rf "${PULL_DIR}" "${EXTRACT_DIR}" "${META_DIR}"
mkdir -p "${PULL_DIR}" "${EXTRACT_DIR}" "${META_DIR}"

echo "Pulling platform contract:"
echo "  ${REF}"

oras pull "${REF}" -o "${PULL_DIR}" | tee "${META_DIR}/oras.pull.log"

# Capture resolved digest for traceability when using a tag (e.g., edge)
RESOLVED_DIGEST="$(grep -Eo 'sha256:[0-9a-f]{64}' "${META_DIR}/oras.pull.log" | tail -n1 || true)"

TARBALL="${PULL_DIR}/dist/platform-contract.tar.gz"
if [[ ! -f "${TARBALL}" ]]; then
  echo "Expected ${TARBALL} not found. Pulled files:" >&2
  find "${PULL_DIR}" -maxdepth 4 -type f -print >&2 || true
  exit 1
fi

tar -xzf "${TARBALL}" -C "${EXTRACT_DIR}"

[[ -f "${EXTRACT_DIR}/platform-contract/contract.env" ]] || {
  echo "Missing platform-contract/contract.env in extracted payload" >&2
  exit 1
}

if [[ -n "${RESOLVED_DIGEST}" ]]; then
  printf '%s\n' "${RESOLVED_DIGEST}" > "${EXTRACT_DIR}/platform-contract/contract.digest"
fi

echo "OK: extracted to ${EXTRACT_DIR}/platform-contract"
