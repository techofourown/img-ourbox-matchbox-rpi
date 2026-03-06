#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check-installer-ssh-smoke.sh <host-or-ip>

Env overrides:
  SSH_PORT=22
  OURBOX_INSTALLER_SSH_MODE=off|key|password|both
  OURBOX_INSTALLER_SSH_USER=ourbox-installer
  OURBOX_INSTALLER_SSH_KEY=/path/to/private_key
  OURBOX_INSTALLER_SSH_PASSWORD=<password>
  OURBOX_INSTALLER_SSH_ALLOW_ROOT=0|1
  ROOT_SSH_PASSWORD=<root password, optional>
  REMOTE_INSTALLER_LOG_PATH=<optional remote log file path for leak scan>
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

host="${1:-}"
[[ -n "${host}" ]] || {
  usage
  exit 1
}

ssh_port="${SSH_PORT:-22}"
ssh_mode="${OURBOX_INSTALLER_SSH_MODE:-key}"
installer_user="${OURBOX_INSTALLER_SSH_USER:-ourbox-installer}"
installer_key="${OURBOX_INSTALLER_SSH_KEY:-}"
installer_password="${OURBOX_INSTALLER_SSH_PASSWORD:-}"
allow_root="${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-0}"
root_password="${ROOT_SSH_PASSWORD:-}"
remote_log_path="${REMOTE_INSTALLER_LOG_PATH:-}"

case "${ssh_mode}" in
  off|key|password|both) ;;
  *) echo "Invalid OURBOX_INSTALLER_SSH_MODE=${ssh_mode}" >&2; exit 1 ;;
esac

need_cmd ssh

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -p "${ssh_port}"
)

check_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 3 "${host}" "${ssh_port}" >/dev/null 2>&1
    return
  fi
  timeout 3 bash -lc "</dev/tcp/${host}/${ssh_port}" >/dev/null 2>&1
}

installer_auth="none"

installer_ssh() {
  local remote_cmd="${1:?remote command required}"
  case "${installer_auth}" in
    key)
      ssh "${ssh_opts[@]}" -i "${installer_key}" "${installer_user}@${host}" "${remote_cmd}"
      ;;
    password)
      SSHPASS="${installer_password}" sshpass -e ssh "${ssh_opts[@]}" "${installer_user}@${host}" "${remote_cmd}"
      ;;
    *)
      echo "No installer auth method selected." >&2
      return 1
      ;;
  esac
}

echo "==> [1/4] Checking sshd is listening on ${host}:${ssh_port}"
check_port || {
  echo "FAIL: sshd is not reachable on ${host}:${ssh_port}" >&2
  exit 1
}
echo "PASS: ssh port reachable"

echo "==> [2/4] Checking ${installer_user} login using mode=${ssh_mode}"
case "${ssh_mode}" in
  off)
    if ssh -o BatchMode=yes "${ssh_opts[@]}" "${installer_user}@${host}" "true" >/dev/null 2>&1; then
      echo "FAIL: ${installer_user} login succeeded but mode=off" >&2
      exit 1
    fi
    echo "PASS: ${installer_user} login blocked as expected (mode=off)"
    ;;
  key)
    [[ -n "${installer_key}" ]] || {
      echo "FAIL: mode=key requires OURBOX_INSTALLER_SSH_KEY" >&2
      exit 1
    }
    ssh -o BatchMode=yes "${ssh_opts[@]}" -i "${installer_key}" "${installer_user}@${host}" "true" >/dev/null
    installer_auth="key"
    echo "PASS: ${installer_user} key login succeeded"
    ;;
  password)
    [[ -n "${installer_password}" ]] || {
      echo "FAIL: mode=password requires OURBOX_INSTALLER_SSH_PASSWORD" >&2
      exit 1
    }
    need_cmd sshpass
    SSHPASS="${installer_password}" sshpass -e ssh "${ssh_opts[@]}" "${installer_user}@${host}" "true" >/dev/null
    installer_auth="password"
    echo "PASS: ${installer_user} password login succeeded"
    ;;
  both)
    if [[ -n "${installer_key}" ]]; then
      ssh -o BatchMode=yes "${ssh_opts[@]}" -i "${installer_key}" "${installer_user}@${host}" "true" >/dev/null
      installer_auth="key"
      echo "PASS: ${installer_user} key login succeeded"
    else
      [[ -n "${installer_password}" ]] || {
        echo "FAIL: mode=both requires key or password input" >&2
        exit 1
      }
      need_cmd sshpass
      SSHPASS="${installer_password}" sshpass -e ssh "${ssh_opts[@]}" "${installer_user}@${host}" "true" >/dev/null
      installer_auth="password"
      echo "PASS: ${installer_user} password login succeeded"
    fi
    ;;
esac

echo "==> [3/4] Checking root login policy (allow_root=${allow_root})"
if [[ "${allow_root}" == "0" ]]; then
  if ssh -o BatchMode=yes "${ssh_opts[@]}" "root@${host}" "true" >/dev/null 2>&1; then
    echo "FAIL: root login succeeded with allow_root=0" >&2
    exit 1
  fi
  if [[ -n "${root_password}" ]]; then
    need_cmd sshpass
    if SSHPASS="${root_password}" sshpass -e ssh "${ssh_opts[@]}" "root@${host}" "true" >/dev/null 2>&1; then
      echo "FAIL: root password login succeeded with allow_root=0" >&2
      exit 1
    fi
  fi
  echo "PASS: root login blocked"
else
  if [[ -n "${root_password}" ]]; then
    need_cmd sshpass
    SSHPASS="${root_password}" sshpass -e ssh "${ssh_opts[@]}" "root@${host}" "true" >/dev/null
    echo "PASS: root password login succeeded"
  else
    echo "WARN: allow_root=1 but ROOT_SSH_PASSWORD not provided; skipped root success check"
  fi
fi

echo "==> [4/4] Checking for leaked secrets in installer logs"
if [[ "${installer_auth}" == "none" ]]; then
  echo "WARN: no installer login method available; skipped remote log scan"
elif [[ -z "${remote_log_path}" ]]; then
  echo "WARN: REMOTE_INSTALLER_LOG_PATH not set; skipped remote log scan"
else
  installer_ssh "if [ -f '${remote_log_path}' ]; then ! grep -E -q 'ourbox-install|password:|sshpass -p ' '${remote_log_path}'; fi"
  echo "PASS: no known secret patterns in ${remote_log_path}"
fi

echo "All SSH smoke checks passed for ${host}"
