#!/usr/bin/env bash
set -euo pipefail

ourbox_installer_ssh_log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" >&2
}

ourbox_installer_ssh_die() {
  ourbox_installer_ssh_log "ERROR: $*"
  exit 1
}

ourbox_installer_ssh_normalize_inputs() {
  OURBOX_INSTALLER_SSH_MODE="${OURBOX_INSTALLER_SSH_MODE:-off}"
  OURBOX_INSTALLER_SSH_USER="${OURBOX_INSTALLER_SSH_USER:-ourbox-installer}"
  OURBOX_INSTALLER_SSH_PASSWORD_HASH="${OURBOX_INSTALLER_SSH_PASSWORD_HASH:-}"
  OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS="${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS:-}"
  OURBOX_INSTALLER_SSH_ALLOW_ROOT="${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-0}"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:-0}"

  case "${OURBOX_INSTALLER_SSH_MODE}" in
    off|key|password|both) ;;
    *) ourbox_installer_ssh_die "invalid OURBOX_INSTALLER_SSH_MODE: ${OURBOX_INSTALLER_SSH_MODE}" ;;
  esac

  case "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" in
    0|1) ;;
    *) ourbox_installer_ssh_die "invalid OURBOX_INSTALLER_SSH_ALLOW_ROOT: ${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" ;;
  esac

  case "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}" in
    0|1) ;;
    *)
      ourbox_installer_ssh_die \
        "invalid OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY: ${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}"
      ;;
  esac

  [[ -n "${OURBOX_INSTALLER_SSH_USER}" ]] \
    || ourbox_installer_ssh_die "OURBOX_INSTALLER_SSH_USER must not be empty"

  if [[ "${OURBOX_INSTALLER_SSH_USER}" =~ [[:space:]:] ]]; then
    ourbox_installer_ssh_die "OURBOX_INSTALLER_SSH_USER must not contain whitespace or ':'"
  fi
}

ourbox_installer_ssh_mode_has_password() {
  local mode="${1:-${OURBOX_INSTALLER_SSH_MODE:-}}"
  case "${mode}" in
    password|both) return 0 ;;
    *) return 1 ;;
  esac
}

ourbox_installer_ssh_mode_has_keys() {
  local mode="${1:-${OURBOX_INSTALLER_SSH_MODE:-}}"
  case "${mode}" in
    key|both) return 0 ;;
    *) return 1 ;;
  esac
}

ourbox_installer_ssh_validate_requested_posture() {
  case "${OURBOX_INSTALLER_SSH_MODE}" in
    off)
      return 0
      ;;
    key)
      [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]] \
        || ourbox_installer_ssh_die "installer SSH mode=key requires authorized keys"
      ;;
    password)
      if [[ -z "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" \
        && "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}" != "1" ]]; then
        ourbox_installer_ssh_die \
          "installer SSH mode=password requires a password hash or local generation support"
      fi
      ;;
    both)
      if [[ -z "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" \
        && -z "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" \
        && "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}" != "1" ]]; then
        ourbox_installer_ssh_die \
          "installer SSH mode=both requires keys, a password hash, or local generation support"
      fi
      ;;
  esac
}

ourbox_installer_ssh_validate_materialized_auth() {
  case "${OURBOX_INSTALLER_SSH_MODE}" in
    off)
      return 0
      ;;
    key)
      [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]] \
        || ourbox_installer_ssh_die "installer SSH mode=key has no materialized key auth path"
      ;;
    password)
      [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]] \
        || ourbox_installer_ssh_die "installer SSH mode=password has no materialized password auth path"
      ;;
    both)
      if [[ -z "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" \
        && -z "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
        ourbox_installer_ssh_die "installer SSH mode=both has no materialized auth path"
      fi
      ;;
  esac
}

ourbox_installer_ssh_ensure_user() {
  if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "off" ]]; then
    return 0
  fi

  if id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
    return 0
  fi

  adduser --disabled-password --gecos "" "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 \
    || useradd -m -s /bin/bash "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 \
    || ourbox_installer_ssh_die "failed to create installer SSH user '${OURBOX_INSTALLER_SSH_USER}'"
}

ourbox_installer_ssh_apply_password_hash_or_lock() {
  if ! id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
    return 0
  fi

  if ourbox_installer_ssh_mode_has_password "${OURBOX_INSTALLER_SSH_MODE}" \
    && [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
    printf '%s:%s\n' "${OURBOX_INSTALLER_SSH_USER}" "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" \
      | chpasswd -e >/dev/null 2>&1 \
      || ourbox_installer_ssh_die "failed to apply installer SSH password hash"
    return 0
  fi

  passwd -l "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 || true
}

ourbox_installer_ssh_apply_authorized_keys() {
  local ssh_home=""
  local ssh_group=""
  local ssh_dir=""
  local ssh_auth_keys=""

  if ! id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v getent >/dev/null 2>&1; then
    ssh_home="$(getent passwd "${OURBOX_INSTALLER_SSH_USER}" | awk -F: '{print $6}' | head -n 1)"
  else
    ssh_home="$(awk -F: -v u="${OURBOX_INSTALLER_SSH_USER}" '$1==u {print $6; exit}' /etc/passwd 2>/dev/null || true)"
  fi
  [[ -n "${ssh_home}" ]] || ssh_home="/home/${OURBOX_INSTALLER_SSH_USER}"
  ssh_group="$(id -gn "${OURBOX_INSTALLER_SSH_USER}" 2>/dev/null || printf '%s' "${OURBOX_INSTALLER_SSH_USER}")"
  ssh_dir="${ssh_home}/.ssh"
  ssh_auth_keys="${ssh_dir}/authorized_keys"

  if ourbox_installer_ssh_mode_has_keys "${OURBOX_INSTALLER_SSH_MODE}" \
    && [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
    install -d -m 0700 "${ssh_dir}" \
      || ourbox_installer_ssh_die "failed to create ${ssh_dir}"
    chown "${OURBOX_INSTALLER_SSH_USER}:${ssh_group}" "${ssh_dir}" \
      || ourbox_installer_ssh_die "failed to set ownership on ${ssh_dir}"
    printf '%s\n' "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" > "${ssh_auth_keys}" \
      || ourbox_installer_ssh_die "failed to write ${ssh_auth_keys}"
    chown "${OURBOX_INSTALLER_SSH_USER}:${ssh_group}" "${ssh_auth_keys}" \
      || ourbox_installer_ssh_die "failed to set ownership on ${ssh_auth_keys}"
    chmod 0600 "${ssh_auth_keys}" \
      || ourbox_installer_ssh_die "failed to chmod ${ssh_auth_keys}"
    return 0
  fi

  rm -f "${ssh_auth_keys}"
}

ourbox_installer_ssh_write_sshd_fragment() {
  local config_file="${1:?config path required}"

  mkdir -p "$(dirname "${config_file}")"

  {
    if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" && "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" == "1" ]]; then
      if ourbox_installer_ssh_mode_has_password "${OURBOX_INSTALLER_SSH_MODE}"; then
        echo "PermitRootLogin prohibit-password"
      else
        echo "PermitRootLogin yes"
      fi
    else
      echo "PermitRootLogin no"
    fi

    if ourbox_installer_ssh_mode_has_password "${OURBOX_INSTALLER_SSH_MODE}"; then
      echo "PasswordAuthentication yes"
    else
      echo "PasswordAuthentication no"
    fi

    echo "PubkeyAuthentication yes"
    echo "KbdInteractiveAuthentication no"
    echo "X11Forwarding no"
    echo "AllowTcpForwarding no"

    if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "off" ]]; then
      echo "AllowUsers nobody"
    elif [[ "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" == "1" ]]; then
      echo "AllowUsers ${OURBOX_INSTALLER_SSH_USER} root"
    else
      echo "AllowUsers ${OURBOX_INSTALLER_SSH_USER}"
    fi
  } > "${config_file}" || ourbox_installer_ssh_die "failed to write ${config_file}"
}

ourbox_installer_ssh_apply_common_state() {
  local config_file="${1:?config path required}"

  ourbox_installer_ssh_ensure_user
  ourbox_installer_ssh_apply_password_hash_or_lock
  ourbox_installer_ssh_apply_authorized_keys
  ourbox_installer_ssh_write_sshd_fragment "${config_file}"
}
