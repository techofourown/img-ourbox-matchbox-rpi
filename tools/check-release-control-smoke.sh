#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/release/official-artifacts.env"

need_cmd bash
need_cmd python3

FIXTURE="${ROOT}/tools/testdata/release-control/candidate-provenance.json"
[[ -f "${FIXTURE}" ]] || die "missing fixture: ${FIXTURE}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DEPLOY_DIR="${TMP}/deploy"
BIN_DIR="${TMP}/bin"
STATE_DIR="${TMP}/state"
mkdir -p "${DEPLOY_DIR}" "${BIN_DIR}" "${STATE_DIR}"

export ORAS_STUB_STATE="${STATE_DIR}"
export ORAS_STUB_LOG="${STATE_DIR}/oras.log"
export ORAS_STUB_CATALOG_TAG="${OFFICIAL_OS_CATALOG_TAG}"

cat > "${BIN_DIR}/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state="${ORAS_STUB_STATE:?}"
log="${ORAS_STUB_LOG:?}"
catalog_tag="${ORAS_STUB_CATALOG_TAG:?}"
mkdir -p "${state}/tags"

sanitize() {
  printf '%s' "$1" | tr '/:@' '___'
}

cmd="${1:?}"
shift || true
printf '%s\t%s\n' "${cmd}" "$*" >> "${log}"

case "${cmd}" in
  resolve)
    ref="${1:?}"
    tag_file="${state}/tags/$(sanitize "${ref}")"
    if [[ -f "${tag_file}" ]]; then
      cat "${tag_file}"
    fi
    ;;
  tag)
    pinned_ref="${1:?}"
    tag="${2:?}"
    repo="${pinned_ref%@*}"
    digest="${pinned_ref##*@}"
    printf '%s\n' "${digest}" > "${state}/tags/$(sanitize "${repo}:${tag}")"
    ;;
  pull)
    ref="${1:?}"
    if [[ "${ref}" == *":${catalog_tag}" ]]; then
      echo "manifest not found" >&2
      exit 1
    fi
    echo "unexpected source-artifact pull: ${ref}" >&2
    exit 97
    ;;
  push)
    ref="${1:?}"
    if [[ "${ref}" != *":${catalog_tag}" ]]; then
      echo "unexpected oras push target: ${ref}" >&2
      exit 98
    fi
    cp "catalog.tsv" "${state}/latest-catalog.tsv"
    ;;
  *)
    echo "unsupported oras command: ${cmd}" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${BIN_DIR}/oras"

export PATH="${BIN_DIR}:${PATH}"
export DEPLOY_DIR
export RELEASE_TAG="v9.9.9"
export CANDIDATE_PROVENANCE_JSON="${FIXTURE}"

"${ROOT}/tools/promote-os-artifact-official.sh" stable
"${ROOT}/tools/promote-installer-artifact-official.sh" stable

for required in \
  os-artifact.ref \
  os-artifact.pinned.ref \
  os-artifact.digest \
  os-artifact.meta.env \
  os-artifact.meta.json \
  os-artifact.promote.json \
  installer-artifact.ref \
  installer-artifact.pinned.ref \
  installer-artifact.digest \
  installer-artifact.meta.env \
  installer-artifact.meta.json \
  installer-artifact.promote.json
do
  [[ -s "${DEPLOY_DIR}/${required}" ]] || die "missing smoke output: ${DEPLOY_DIR}/${required}"
done

bash -euo pipefail -c '
  source "$1"
  [[ "${GITHUB_WORKFLOW}" == "Official Candidate Build & Publish (Matchbox)" ]]
' _ "${DEPLOY_DIR}/os-artifact.meta.env"

bash -euo pipefail -c '
  source "$1"
  [[ "${GITHUB_WORKFLOW}" == "Official Candidate Build & Publish (Matchbox)" ]]
' _ "${DEPLOY_DIR}/installer-artifact.meta.env"

[[ -f "${STATE_DIR}/latest-catalog.tsv" ]] || die "catalog push did not write latest-catalog.tsv"
grep -F $'stable	v9.9.9-rpi	' "${STATE_DIR}/latest-catalog.tsv" >/dev/null \
  || die "catalog row missing expected Matchbox stable entry"

if grep -F 'pull	ghcr.io/techofourown/ourbox-matchbox-os@sha256:' "${ORAS_STUB_LOG}" >/dev/null; then
  die "OS promotion attempted to pull the candidate pinned ref"
fi
if grep -F 'pull	ghcr.io/techofourown/ourbox-matchbox-installer@sha256:' "${ORAS_STUB_LOG}" >/dev/null; then
  die "Installer promotion attempted to pull the candidate pinned ref"
fi

"${ROOT}/tools/promote-os-artifact-official.sh" stable
"${ROOT}/tools/promote-installer-artifact-official.sh" stable

log "Release-control smoke passed"
