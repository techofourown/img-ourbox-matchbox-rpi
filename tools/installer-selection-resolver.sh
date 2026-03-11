#!/usr/bin/env bash
set -euo pipefail

# Shared installer-selection policy lives upstream in sw-ourbox-os.
# Consumers may vendor this file into target-specific installer images, but the
# contract and reference implementation are defined here.

ourbox_selection_log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" >&2
}

ourbox_selection_die() {
  ourbox_selection_log "ERROR: $*"
  exit 1
}

ourbox_selection_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || ourbox_selection_die "missing required command: $1"
}

ourbox_selection_reset_state() {
  OURBOX_INSTALL_DEFAULTS_SOURCE="baked"
  OURBOX_INSTALL_DEFAULTS_PROFILE=""
  OURBOX_INSTALL_SELECTION_SOURCE=""
  OURBOX_RELEASE_CHANNEL=""
  OURBOX_CATALOG_REF=""
  OURBOX_SELECTED_REF=""
  OURBOX_PULL_REF=""
  OURBOX_OS_ARTIFACT_SOURCE="registry"
  OURBOX_OS_ARTIFACT_REF=""
  OURBOX_OS_ARTIFACT_DIGEST=""
}

ourbox_selection_is_clean_single_line_ref() {
  local ref="${1:-}"
  [[ -n "${ref}" ]] || return 1
  [[ "${ref}" != *$'\n'* ]] || return 1
  [[ "${ref}" != *$'\r'* ]] || return 1
  [[ "${ref}" != *$'\t'* ]] || return 1
  [[ "${ref}" != *" "* ]] || return 1
  return 0
}

ourbox_selection_is_digest_pinned_ref() {
  local ref="${1:-}"
  ourbox_selection_is_clean_single_line_ref "${ref}" || return 1
  [[ "${ref}" =~ ^[^[:space:]]+@sha256:[0-9a-f]{64}$ ]] || return 1
  return 0
}

ourbox_selection_channel_tag() {
  local channel="${1:-}"
  local target="${OS_TARGET:-}"
  local tag=""
  case "${channel}" in
    stable) tag="${CHANNEL_STABLE_TAG:-}"; [[ -n "${tag}" ]] || tag="${target}-stable" ;;
    beta) tag="${CHANNEL_BETA_TAG:-}"; [[ -n "${tag}" ]] || tag="${target}-beta" ;;
    nightly) tag="${CHANNEL_NIGHTLY_TAG:-}"; [[ -n "${tag}" ]] || tag="${target}-nightly" ;;
    exp-labs) tag="${CHANNEL_EXP_LABS_TAG:-}"; [[ -n "${tag}" ]] || tag="${target}-exp-labs" ;;
    *) tag="${target}-${channel}" ;;
  esac
  [[ -n "${tag}" ]] || ourbox_selection_die "unable to resolve channel tag for '${channel}'"
  printf '%s\n' "${tag}"
}

ourbox_selection_load_remote_install_defaults() {
  local pull_dir="$1"
  local extract_dir="$2"
  local override_env="${3:-}"
  local baked_os_default_ref="${OS_DEFAULT_REF:-}"
  local expected_installer_id="${INSTALLER_ID:-}"

  OURBOX_INSTALL_DEFAULTS_SOURCE="baked"
  OURBOX_INSTALL_DEFAULTS_PROFILE=""

  [[ -n "${INSTALL_DEFAULTS_REF:-}" ]] || return 0

  ourbox_selection_need_cmd oras
  rm -rf "${pull_dir}" "${extract_dir}"
  mkdir -p "${pull_dir}" "${extract_dir}"

  ourbox_selection_log "Pulling installer defaults: ${INSTALL_DEFAULTS_REF}"
  if ! oras pull "${INSTALL_DEFAULTS_REF}" -o "${pull_dir}" >/dev/null 2>&1; then
    ourbox_selection_log "Install defaults pull failed; using baked defaults."
    return 0
  fi

  local tarball=""
  if [[ -f "${pull_dir}/dist/install-defaults.tar.gz" ]]; then
    tarball="${pull_dir}/dist/install-defaults.tar.gz"
  else
    tarball="$(find "${pull_dir}" -maxdepth 4 -type f -name 'install-defaults.tar.gz' | head -n 1 || true)"
  fi
  [[ -n "${tarball}" && -f "${tarball}" ]] || {
    ourbox_selection_log "Install defaults artifact missing tarball; using baked defaults."
    return 0
  }

  if ! tar -xzf "${tarball}" -C "${extract_dir}" >/dev/null 2>&1; then
    ourbox_selection_log "Install defaults tar extraction failed; using baked defaults."
    return 0
  fi

  [[ -f "${extract_dir}/install-defaults/schema.env" ]] || {
    ourbox_selection_log "Install defaults artifact missing schema.env; using baked defaults."
    return 0
  }
  [[ -f "${extract_dir}/install-defaults/manifest.env" ]] || {
    ourbox_selection_log "Install defaults artifact missing manifest.env; using baked defaults."
    return 0
  }

  local profile="${extract_dir}/install-defaults/defaults/${expected_installer_id}.env"
  if [[ ! -f "${profile}" ]]; then
    ourbox_selection_log "No install-defaults profile for installer '${expected_installer_id}'; using baked defaults."
    return 0
  fi

  # shellcheck disable=SC1090
  source "${profile}"
  if [[ -n "${override_env}" && -f "${override_env}" ]]; then
    # Re-apply local overrides so operators keep final control.
    # shellcheck disable=SC1090
    source "${override_env}"
  fi

  if declare -F normalize_payload_config >/dev/null 2>&1; then
    normalize_payload_config
  fi

  # A baked pinned default ref remains authoritative unless the remote profile
  # explicitly replaces it with another non-empty ref.
  if [[ -n "${baked_os_default_ref}" && -z "${OS_DEFAULT_REF:-}" ]]; then
    OS_DEFAULT_REF="${baked_os_default_ref}"
  fi

  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_INSTALL_DEFAULTS_SOURCE="remote"
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_INSTALL_DEFAULTS_PROFILE="${profile}"
  ourbox_selection_log "Applied install-defaults profile for '${expected_installer_id}'."
}

ourbox_selection_pull_catalog() {
  local dst="$1"
  local ref="${OS_REPO}:${OS_CATALOG_TAG}"

  if [[ "${OS_CATALOG_ENABLED:-1}" != "1" ]]; then
    return 1
  fi

  ourbox_selection_need_cmd oras
  rm -rf "${dst}"
  mkdir -p "${dst}"

  ourbox_selection_log "Pulling catalog: ${ref}"
  if ! oras pull "${ref}" -o "${dst}" >/dev/null 2>&1; then
    return 1
  fi
  [[ -f "${dst}/catalog.tsv" ]] || return 1

  OURBOX_CATALOG_REF="${ref}"
  return 0
}

ourbox_selection_catalog_entries() {
  local catalog_tsv="$1"
  [[ -f "${catalog_tsv}" ]] || return 1

  awk -F'\t' '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        idx[$i] = i
      }
      if (!idx["channel"] || !idx["tag"] || !idx["created"] || !idx["version"] || !idx["platform_contract_digest"] || !idx["pinned_ref"]) {
        exit 0
      }
      next
    }
    {
      pinned = $(idx["pinned_ref"])
      created = $(idx["created"])
      if (created == "") {
        next
      }
      if (pinned !~ /^[^[:space:]]+@sha256:[0-9a-f]{64}$/) {
        next
      }
      print $(idx["channel"]) "\t" $(idx["tag"]) "\t" created "\t" $(idx["version"]) "\t" $(idx["platform_contract_digest"]) "\t" pinned
    }
  ' "${catalog_tsv}" | sort -t $'\t' -k3,3r -k2,2r
}

ourbox_selection_catalog_newest_ref() {
  local catalog_tsv="$1"
  local channel="$2"
  local row=""

  row="$(ourbox_selection_catalog_entries "${catalog_tsv}" | awk -F'\t' -v ch="${channel}" -v target="${OS_TARGET:-}" '
    $1 == ch || (target != "" && ch ~ /^(stable|beta|nightly|exp-labs)$/ && $1 == target "-" ch) { print; exit }
  ' || true)"
  [[ -n "${row}" ]] || return 1
  printf '%s\n' "${row##*$'\t'}"
}

ourbox_selection_resolve_channel_ref() {
  local catalog_dir="$1"
  local channel="$2"
  local channel_tag_ref=""
  local catalog_tsv=""
  local catalog_ref=""

  OURBOX_INSTALL_SELECTION_SOURCE=""
  OURBOX_RELEASE_CHANNEL=""
  OURBOX_SELECTED_REF=""
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_CATALOG_REF=""

  channel_tag_ref="${OS_REPO}:$(ourbox_selection_channel_tag "${channel}")"

  if [[ "${OS_CATALOG_ENABLED:-1}" == "1" ]]; then
    if ourbox_selection_pull_catalog "${catalog_dir}"; then
      catalog_tsv="${catalog_dir}/catalog.tsv"
      catalog_ref="$(ourbox_selection_catalog_newest_ref "${catalog_tsv}" "${channel}" || true)"
      if ourbox_selection_is_digest_pinned_ref "${catalog_ref}"; then
        OURBOX_INSTALL_SELECTION_SOURCE="catalog"
        OURBOX_RELEASE_CHANNEL="${channel}"
        OURBOX_SELECTED_REF="${catalog_ref}"
        return 0
      fi
      ourbox_selection_log "Catalog has no valid digest-pinned entry for channel '${channel}'; falling back to channel tag."
    else
      ourbox_selection_log "Catalog unavailable; falling back to channel tag."
    fi
  fi

  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_INSTALL_SELECTION_SOURCE="channel-tag"
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_RELEASE_CHANNEL="${channel}"
  OURBOX_SELECTED_REF="${channel_tag_ref}"
}

ourbox_selection_determine_default_ref() {
  local catalog_dir="$1"

  OURBOX_INSTALL_SELECTION_SOURCE=""
  OURBOX_RELEASE_CHANNEL=""
  OURBOX_SELECTED_REF=""
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_CATALOG_REF=""

  if [[ -n "${OS_REF:-}" ]]; then
    OURBOX_INSTALL_SELECTION_SOURCE="os-ref"
    OURBOX_SELECTED_REF="${OS_REF}"
    return 0
  fi

  if [[ -n "${OS_DEFAULT_REF:-}" ]]; then
    OURBOX_INSTALL_SELECTION_SOURCE="os-default-ref"
    OURBOX_SELECTED_REF="${OS_DEFAULT_REF}"
    return 0
  fi

  ourbox_selection_resolve_channel_ref "${catalog_dir}" "${OS_CHANNEL}"
}

ourbox_selection_ref_from_tag() {
  local tag="$1"
  printf '%s:%s\n' "${OS_REPO}" "${tag}"
}

ourbox_selection_show_default_choice() {
  local ref="$1"

  echo
  if [[ "${OURBOX_INSTALL_DEFAULTS_SOURCE}" == "remote" ]]; then
    echo "Install defaults: remote (${INSTALL_DEFAULTS_REF})"
    echo "Profile        : ${OURBOX_INSTALL_DEFAULTS_PROFILE}"
  else
    echo "Install defaults: baked defaults"
  fi
  echo "Default source : ${OURBOX_INSTALL_SELECTION_SOURCE:-pending}"
  echo "Default: install '${ref}'"
  echo "Options:"
  echo "  [ENTER] Use default"
  echo "  c       Choose channel (prefers newest catalog row for that lane)"
  echo "  l       List from catalog (if available)"
  echo "  r       Enter custom OCI ref (tag or digest)"
  echo "  o       Override OS repo (custom registry/fork)"
  echo "  q       Quit"
  echo
}

ourbox_selection_override_repo_interactive() {
  local next_repo=""
  local next_catalog="${OS_TARGET}-catalog"
  local user_catalog=""

  read -r -p "Enter OCI repo (e.g., ghcr.io/org/ourbox-os): " next_repo
  [[ -n "${next_repo}" ]] || {
    ourbox_selection_log "Repository cannot be empty."
    return 1
  }

  OS_REPO="${next_repo}"

  # A repo override intentionally clears pinned defaults from upstream profile.
  OS_REF=""
  OS_DEFAULT_REF=""

  read -r -p "Catalog tag [${next_catalog}]: " user_catalog
  if [[ -n "${user_catalog}" ]]; then
    OS_CATALOG_TAG="${user_catalog}"
  else
    OS_CATALOG_TAG="${next_catalog}"
  fi

  ourbox_selection_log "OS repo override set to ${OS_REPO}"
}

ourbox_selection_choose_channel_interactive() {
  local catalog_dir="$1"
  local pick=""
  local custom_tag=""

  echo "Channels:"
  echo "  1) stable (${CHANNEL_STABLE_TAG:-$(ourbox_selection_channel_tag stable)}) (recommended)"
  echo "  2) beta (${CHANNEL_BETA_TAG:-$(ourbox_selection_channel_tag beta)})"
  echo "  3) nightly (${CHANNEL_NIGHTLY_TAG:-$(ourbox_selection_channel_tag nightly)})"
  echo "  4) exp-labs (${CHANNEL_EXP_LABS_TAG:-$(ourbox_selection_channel_tag exp-labs)})"
  echo "  5) custom tag name"

  read -r -p "Select channel [1-5]: " pick
  case "${pick}" in
    1|"")
      ourbox_selection_resolve_channel_ref "${catalog_dir}" "stable"
      ;;
    2)
      ourbox_selection_resolve_channel_ref "${catalog_dir}" "beta"
      ;;
    3)
      ourbox_selection_resolve_channel_ref "${catalog_dir}" "nightly"
      ;;
    4)
      ourbox_selection_resolve_channel_ref "${catalog_dir}" "exp-labs"
      ;;
    5)
      read -r -p "Enter tag: " custom_tag
      [[ -n "${custom_tag}" ]] || {
        ourbox_selection_log "Tag cannot be empty."
        return 1
      }
      OURBOX_SELECTED_REF="$(ourbox_selection_ref_from_tag "${custom_tag}")"
      OURBOX_INSTALL_SELECTION_SOURCE="channel-tag"
      OURBOX_RELEASE_CHANNEL=""
      ;;
    *)
      ourbox_selection_log "Invalid choice."
      return 1
      ;;
  esac
}

ourbox_selection_select_from_catalog_interactive() {
  local catalog_dir="$1"
  local catalog_tsv=""
  local pick=""
  local chosen=""
  local channel=""
  local tag=""
  local created=""
  local version=""
  local contract=""
  local pinned_ref=""
  local i=1
  local -a entries=()

  OURBOX_CATALOG_REF=""
  ourbox_selection_pull_catalog "${catalog_dir}" || {
    ourbox_selection_log "Catalog unavailable; skipping list."
    return 1
  }

  catalog_tsv="${catalog_dir}/catalog.tsv"
  mapfile -t entries < <(ourbox_selection_catalog_entries "${catalog_tsv}")
  if [[ "${#entries[@]}" -eq 0 ]]; then
    ourbox_selection_log "Catalog pulled (${OURBOX_CATALOG_REF}) but contained no entries."
    return 1
  fi

  echo
  echo "Catalog entries (${OURBOX_CATALOG_REF}):"
  for chosen in "${entries[@]}"; do
    IFS=$'\t' read -r channel tag created version contract pinned_ref <<<"${chosen}"
    printf "  %d) %-12s %-30s %s %s %s\n" "${i}" "${channel}" "${tag}" "${version}" "${created}" "${contract}"
    i=$((i + 1))
  done

  read -r -p "Choose entry [1-${#entries[@]}] (or ENTER to cancel): " pick
  [[ -n "${pick}" ]] || return 1
  [[ "${pick}" =~ ^[0-9]+$ ]] || {
    ourbox_selection_log "Invalid selection."
    return 1
  }
  if (( pick < 1 || pick > ${#entries[@]} )); then
    ourbox_selection_log "Selection out of range."
    return 1
  fi

  chosen="${entries[$((pick - 1))]}"
  IFS=$'\t' read -r channel tag created version contract pinned_ref <<<"${chosen}"
  OURBOX_SELECTED_REF="${pinned_ref}"
  OURBOX_INSTALL_SELECTION_SOURCE="catalog"
  OURBOX_RELEASE_CHANNEL="${channel}"
  ourbox_selection_log "Selected ${OURBOX_SELECTED_REF} (channel=${channel}, version=${version}, contract=${contract})"
}

ourbox_selection_prompt_custom_ref_interactive() {
  local ref=""

  read -r -p "Enter full OCI ref (e.g., repo:tag or repo@sha256:...): " ref
  ourbox_selection_is_clean_single_line_ref "${ref}" || {
    ourbox_selection_log "Ref must be a single-line OCI ref without whitespace."
    return 1
  }

  OURBOX_SELECTED_REF="${ref}"
  OURBOX_INSTALL_SELECTION_SOURCE="operator-override"
  OURBOX_RELEASE_CHANNEL=""
}

ourbox_selection_interactive_select_ref() {
  local catalog_root="$1"
  local default_catalog_dir="${catalog_root}/default"
  local channel_catalog_dir="${catalog_root}/channel"
  local list_catalog_dir="${catalog_root}/list"
  local choice=""
  local default_ref=""
  local default_source=""
  local default_channel=""

  OURBOX_SELECTED_REF=""
  OURBOX_INSTALL_SELECTION_SOURCE=""
  OURBOX_RELEASE_CHANNEL=""

  while [[ -z "${OURBOX_SELECTED_REF}" ]]; do
    ourbox_selection_determine_default_ref "${default_catalog_dir}"
    default_ref="${OURBOX_SELECTED_REF}"
    default_source="${OURBOX_INSTALL_SELECTION_SOURCE}"
    default_channel="${OURBOX_RELEASE_CHANNEL}"
    OURBOX_SELECTED_REF=""

    ourbox_selection_show_default_choice "${default_ref}"
    read -r -p "Choice: " choice

    case "${choice}" in
      "")
        OURBOX_SELECTED_REF="${default_ref}"
        OURBOX_INSTALL_SELECTION_SOURCE="${default_source}"
        OURBOX_RELEASE_CHANNEL="${default_channel}"
        ;;
      c)
        ourbox_selection_choose_channel_interactive "${channel_catalog_dir}" || true
        ;;
      l)
        ourbox_selection_select_from_catalog_interactive "${list_catalog_dir}" || true
        ;;
      r)
        ourbox_selection_prompt_custom_ref_interactive || true
        ;;
      o)
        ourbox_selection_override_repo_interactive || true
        ;;
      q|Q)
        ourbox_selection_die "Install aborted by user"
        ;;
      *)
        ourbox_selection_log "Unknown option."
        ;;
    esac
  done
}

ourbox_selection_ref_repo_base() {
  local ref="$1"
  local tail="${ref##*/}"

  if [[ "${ref}" == *@* ]]; then
    printf '%s\n' "${ref%%@*}"
    return 0
  fi

  # Registry ports live before the last slash and must be preserved. Only the
  # tag separator in the final path segment should be removed here.
  if [[ "${tail}" == *:* ]]; then
    printf '%s\n' "${ref%:*}"
  else
    printf '%s\n' "${ref}"
  fi
}

ourbox_selection_finalize_registry_ref() {
  local selected_ref="$1"
  local selected_ref_q=""
  local resolved_digest=""
  local repo_base=""

  if ! ourbox_selection_is_clean_single_line_ref "${selected_ref}"; then
    printf -v selected_ref_q '%q' "${selected_ref}"
    ourbox_selection_die "invalid selected OS artifact ref (must be non-empty, single-line, no whitespace): ${selected_ref_q}"
  fi

  ourbox_selection_need_cmd oras

  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_SELECTED_REF="${selected_ref}"
  OURBOX_PULL_REF="${selected_ref}"
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_OS_ARTIFACT_SOURCE="registry"
  # shellcheck disable=SC2034  # output state consumed by the sourcing installer
  OURBOX_OS_ARTIFACT_REF="${selected_ref}"
  OURBOX_OS_ARTIFACT_DIGEST=""

  if ourbox_selection_is_digest_pinned_ref "${selected_ref}"; then
    OURBOX_OS_ARTIFACT_DIGEST="${selected_ref##*@}"
    return 0
  fi

  ourbox_selection_log "Resolving to immutable digest: ${selected_ref}"
  if resolved_digest="$(oras resolve "${selected_ref}" 2>/dev/null)" \
    && [[ "${resolved_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    OURBOX_OS_ARTIFACT_DIGEST="${resolved_digest}"
    repo_base="$(ourbox_selection_ref_repo_base "${selected_ref}")"
    OURBOX_PULL_REF="${repo_base}@${resolved_digest}"
    ourbox_selection_log "Resolved: ${resolved_digest}"
    return 0
  fi

  if [[ "${OURBOX_ALLOW_UNRESOLVED_PULL:-0}" == "1" ]]; then
    ourbox_selection_log "WARNING: oras resolve failed; pulling by tag (OURBOX_ALLOW_UNRESOLVED_PULL=1)"
    ourbox_selection_log "WARNING: artifact identity will not be captured in provenance"
    # shellcheck disable=SC2034  # output state consumed by the sourcing installer
    OURBOX_OS_ARTIFACT_DIGEST="unresolved"
    # shellcheck disable=SC2034  # output state consumed by the sourcing installer
    OURBOX_PULL_REF="${selected_ref}"
    return 0
  fi

  ourbox_selection_die "Cannot establish artifact identity: oras resolve failed for ${selected_ref}
  The installer requires a digest-pinned artifact ref to ensure provenance.
  Options:
    1. Use a digest-pinned ref (catalog or OS_DEFAULT_REF usually provides this)
    2. Check registry connectivity and retry
    3. Set OURBOX_ALLOW_UNRESOLVED_PULL=1 to skip this check (dev/testing only)"
}
