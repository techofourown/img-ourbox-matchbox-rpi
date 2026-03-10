#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/installer-ssh-helper.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

reset_env() {
  unset OURBOX_INSTALLER_SSH_MODE
  unset OURBOX_INSTALLER_SSH_USER
  unset OURBOX_INSTALLER_SSH_PASSWORD_HASH
  unset OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS
  unset OURBOX_INSTALLER_SSH_ALLOW_ROOT
  unset OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY
}

expect_success() {
  local label="$1"
  shift
  if ! "$@"; then
    printf 'FAIL: %s\n' "${label}" >&2
    exit 1
  fi
}

expect_failure() {
  local label="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "${label}" >&2
    exit 1
  fi
}

test_official_posture_passes() {
  local config="${TMP}/official.conf"

  reset_env
  OURBOX_INSTALLER_SSH_MODE="off"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="0"
  ourbox_installer_ssh_normalize_inputs
  expect_success "official requested posture" ourbox_installer_ssh_validate_requested_posture
  expect_success "official materialized auth" ourbox_installer_ssh_validate_materialized_auth
  ourbox_installer_ssh_write_sshd_fragment "${config}"
  grep -qx 'PermitRootLogin no' "${config}"
  grep -qx 'PasswordAuthentication no' "${config}"
  grep -qx 'AllowUsers nobody' "${config}"
}

test_key_without_keys_fails() {
  reset_env
  OURBOX_INSTALLER_SSH_MODE="key"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="0"
  ourbox_installer_ssh_normalize_inputs
  expect_failure "key without keys fails requested posture" ourbox_installer_ssh_validate_requested_posture
}

test_password_without_hash_fails() {
  reset_env
  OURBOX_INSTALLER_SSH_MODE="password"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="0"
  ourbox_installer_ssh_normalize_inputs
  expect_failure "password without hash fails requested posture" ourbox_installer_ssh_validate_requested_posture
}

test_both_without_auth_fails() {
  reset_env
  OURBOX_INSTALLER_SSH_MODE="both"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="0"
  ourbox_installer_ssh_normalize_inputs
  expect_failure "both without auth fails requested posture" ourbox_installer_ssh_validate_requested_posture
}

test_explicit_support_posture_with_hash_passes() {
  local config="${TMP}/support.conf"

  reset_env
  OURBOX_INSTALLER_SSH_MODE="password"
  OURBOX_INSTALLER_SSH_PASSWORD_HASH="\$6\$testsalt\$0123456789abcdef"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="0"
  ourbox_installer_ssh_normalize_inputs
  expect_success "support requested posture" ourbox_installer_ssh_validate_requested_posture
  expect_success "support materialized auth" ourbox_installer_ssh_validate_materialized_auth
  ourbox_installer_ssh_write_sshd_fragment "${config}"
  grep -qx 'PasswordAuthentication yes' "${config}"
  grep -qx 'AllowUsers ourbox-installer' "${config}"
}

main() {
  test_official_posture_passes
  test_key_without_keys_fails
  test_password_without_hash_fails
  test_both_without_auth_fails
  test_explicit_support_posture_with_hash_passes
  printf 'installer ssh policy smoke: PASS\n'
}

main "$@"
