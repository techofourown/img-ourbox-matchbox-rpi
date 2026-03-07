#!/usr/bin/env bash
# Shared Matchbox storage-role and DATA-state flow.
#
# This is the single authoritative place for:
# - detecting the two NVMe disks
# - choosing SYSTEM vs DATA roles
# - repurposing a former DATA disk as SYSTEM
# - preserving, resetting, or erasing existing DATA state
#
# Callers must provide:
# - log
# - die
# - prompt_confirm_exact

: "${MATCHBOX_DATA_CHECK_MP:=/tmp/matchbox-data-check}"

# shellcheck disable=SC2034  # outputs consumed by callers sourcing this helper
MATCHBOX_DATA_HAS_CONTENT=0
MATCHBOX_DATA_BOOTSTRAP_DONE=0
MATCHBOX_DATA_BOOTSTRAP_DONE_TS=""
MATCHBOX_DATA_DEVICE_ID=""
MATCHBOX_SYSTEM_DISK=""
MATCHBOX_DATA_DISK=""
MATCHBOX_DATA_PART=""

matchbox_storage_cmd() {
  local sudo_prefix="${MATCHBOX_SUDO:-${SUDO:-}}"
  local -a prefix=()

  if [[ -n "${sudo_prefix}" ]]; then
    read -r -a prefix <<< "${sudo_prefix}"
    "${prefix[@]}" "$@"
    return
  fi

  "$@"
}

matchbox_require_callback() {
  local callback="$1"
  declare -F "${callback}" >/dev/null 2>&1 || die "missing required callback: ${callback}"
}

matchbox_nvme_disks() {
  lsblk -dn -o NAME,TYPE \
    | awk '$2=="disk" && $1 ~ /^nvme[0-9]+n[0-9]+$/ {print "/dev/"$1}'
}

matchbox_show_nvme_summary() {
  local disks=("$@")
  echo
  echo "NVMe disks detected:"
  echo
  lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${disks[@]}" || true
  echo
}

matchbox_unmount_anything_on_disk() {
  local disk="$1"

  while read -r name mp; do
    [[ -n "${mp}" ]] || continue
    matchbox_storage_cmd umount "/dev/${name}" >/dev/null 2>&1 \
      || matchbox_storage_cmd umount "${mp}" >/dev/null 2>&1 \
      || true
  done < <(lsblk -nr -o NAME,MOUNTPOINT "${disk}" | awk 'NF==2 && $2!="" {print $1, $2}')
}

matchbox_require_unmounted_disk() {
  local disk="$1"

  matchbox_unmount_anything_on_disk "${disk}"
  if lsblk -nr -o MOUNTPOINT "${disk}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${disk}" || true
    die "could not unmount all partitions on ${disk}"
  fi
}

matchbox_zero_head_tail() {
  local disk="$1"
  local zero_mib="${ZERO_MIB:-32}"
  local size_bytes total_mib seek_mib

  matchbox_storage_cmd dd if=/dev/zero of="${disk}" bs=1M count="${zero_mib}" conv=fsync status=progress

  size_bytes="$(matchbox_storage_cmd blockdev --getsize64 "${disk}")"
  total_mib="$((size_bytes / 1024 / 1024))"
  if (( total_mib > zero_mib )); then
    seek_mib="$((total_mib - zero_mib))"
    matchbox_storage_cmd dd if=/dev/zero of="${disk}" bs=1M count="${zero_mib}" seek="${seek_mib}" conv=fsync status=progress
  fi
}

matchbox_wait_for_block_device() {
  local dev="$1"

  for _i in $(seq 1 20); do
    [[ -b "${dev}" ]] && return 0
    sleep 0.5
  done

  return 1
}

matchbox_label_part_on_disk() {
  local label="$1"
  local disk="$2"
  local part="" part_label=""

  while read -r part; do
    [[ -n "${part}" ]] || continue
    part_label="$(matchbox_storage_cmd blkid -o value -s LABEL "${part}" 2>/dev/null || true)"
    if [[ "${part_label}" == "${label}" ]]; then
      readlink -f "${part}"
      return 0
    fi
  done < <(lsblk -ln -o PATH,TYPE "${disk}" | awk '$2=="part" {print $1}')

  echo ""
}

matchbox_disk_role_hint() {
  local disk="$1"
  local data_part=""

  data_part="$(matchbox_label_part_on_disk OURBOX_DATA "${disk}")"
  if [[ -n "${data_part}" ]]; then
    echo "contains OURBOX_DATA on ${data_part}"
  else
    echo "no OURBOX_DATA label detected"
  fi
}

matchbox_pick_other_disk() {
  local a="$1" b="$2" chosen="$3"

  if [[ "${chosen}" == "${a}" ]]; then
    echo "${b}"
  else
    echo "${a}"
  fi
}

matchbox_choose_system_disk() {
  local disks=("$@")
  local pick="" note=""

  matchbox_show_nvme_summary "${disks[@]}"
  echo "Choose SYSTEM disk (this disk will be wiped and flashed):"

  note="$(matchbox_disk_role_hint "${disks[0]}")"
  printf '  1) %s  [%s]\n' "${disks[0]}" "${note}"
  note="$(matchbox_disk_role_hint "${disks[1]}")"
  printf '  2) %s  [%s]\n' "${disks[1]}" "${note}"

  read -r -p "Enter 1 or 2: " pick
  case "${pick}" in
    1) echo "${disks[0]}" ;;
    2) echo "${disks[1]}" ;;
    *) die "invalid choice" ;;
  esac
}

matchbox_wipe_disk_to_blank_state() {
  local disk="$1"

  matchbox_require_unmounted_disk "${disk}"
  if command -v blkdiscard >/dev/null 2>&1; then
    matchbox_storage_cmd blkdiscard -f "${disk}" >/dev/null 2>&1 || true
  fi
  matchbox_storage_cmd wipefs -a "${disk}" >/dev/null 2>&1 || true
  matchbox_zero_head_tail "${disk}"
  sync
}

matchbox_init_data_disk_ext4_labeled() {
  local disk="$1"
  local ask_confirm="${2:-1}"
  local part="" label=""

  if [[ "${ask_confirm}" == "1" ]]; then
    prompt_confirm_exact "ERASE-DATA" "Type ERASE-DATA to confirm DATA disk erase:"
  fi

  log "Initializing DATA disk: ${disk}"
  matchbox_wipe_disk_to_blank_state "${disk}"

  matchbox_storage_cmd parted -s "${disk}" mklabel gpt
  matchbox_storage_cmd parted -s "${disk}" mkpart primary ext4 1MiB 100%
  matchbox_storage_cmd partprobe "${disk}" || true

  part="${disk}p1"
  matchbox_wait_for_block_device "${part}" || die "partition device did not appear: ${part}"
  matchbox_storage_cmd mkfs.ext4 -F -L OURBOX_DATA "${part}"
  sync

  label="$(matchbox_storage_cmd blkid -o value -s LABEL "${part}" 2>/dev/null || true)"
  [[ "${label}" == "OURBOX_DATA" ]] || die "mkfs completed but LABEL is not OURBOX_DATA on ${part} (got: ${label:-<empty>})"
}

matchbox_cleanup_data_check_mp() {
  if mountpoint -q "${MATCHBOX_DATA_CHECK_MP}"; then
    matchbox_storage_cmd umount "${MATCHBOX_DATA_CHECK_MP}" >/dev/null 2>&1 || true
  fi
}

matchbox_inspect_data_partition() {
  local dpart="$1"
  local found=""

  MATCHBOX_DATA_HAS_CONTENT=0
  MATCHBOX_DATA_BOOTSTRAP_DONE=0
  MATCHBOX_DATA_BOOTSTRAP_DONE_TS=""
  MATCHBOX_DATA_DEVICE_ID=""

  mkdir -p "${MATCHBOX_DATA_CHECK_MP}"
  matchbox_cleanup_data_check_mp

  if ! matchbox_storage_cmd mount -t ext4 -o ro,noload "${dpart}" "${MATCHBOX_DATA_CHECK_MP}" >/dev/null 2>&1; then
    matchbox_storage_cmd mount -t ext4 -o ro "${dpart}" "${MATCHBOX_DATA_CHECK_MP}" >/dev/null 2>&1 || return 1
  fi

  if [[ -f "${MATCHBOX_DATA_CHECK_MP}/state/bootstrap.done" ]]; then
    MATCHBOX_DATA_BOOTSTRAP_DONE=1
    MATCHBOX_DATA_BOOTSTRAP_DONE_TS="$(cat "${MATCHBOX_DATA_CHECK_MP}/state/bootstrap.done" 2>/dev/null || true)"
  fi

  if [[ -f "${MATCHBOX_DATA_CHECK_MP}/device/device_id" ]]; then
    MATCHBOX_DATA_DEVICE_ID="$(cat "${MATCHBOX_DATA_CHECK_MP}/device/device_id" 2>/dev/null || true)"
  fi

  found="$(matchbox_storage_cmd find "${MATCHBOX_DATA_CHECK_MP}" -mindepth 1 -maxdepth 1 ! -name lost+found -print -quit 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    MATCHBOX_DATA_HAS_CONTENT=1
  fi

  matchbox_cleanup_data_check_mp
  return 0
}

matchbox_reset_data_bootstrap_marker() {
  local dpart="$1"

  mkdir -p "${MATCHBOX_DATA_CHECK_MP}"
  matchbox_cleanup_data_check_mp

  matchbox_storage_cmd mount -t ext4 -o rw "${dpart}" "${MATCHBOX_DATA_CHECK_MP}"
  matchbox_storage_cmd rm -f "${MATCHBOX_DATA_CHECK_MP}/state/bootstrap.done"
  sync
  matchbox_cleanup_data_check_mp
  log "Reset bootstrap marker on DATA: removed /state/bootstrap.done"
}

matchbox_prepare_storage_layout() {
  local disks=("$@")
  local sys_disk="" ddisk="" dpart="" sys_data_part="" fstype="" data_choice=""

  matchbox_require_callback prompt_confirm_exact

  sys_disk="$(matchbox_choose_system_disk "${disks[@]}")"
  ddisk="$(matchbox_pick_other_disk "${disks[0]}" "${disks[1]}" "${sys_disk}")"
  dpart="$(matchbox_label_part_on_disk OURBOX_DATA "${ddisk}")"
  sys_data_part="$(matchbox_label_part_on_disk OURBOX_DATA "${sys_disk}")"

  if [[ -n "${sys_data_part}" ]]; then
    echo
    echo "Selected SYSTEM disk ${sys_disk} currently carries LABEL=OURBOX_DATA on ${sys_data_part}."
    if [[ -n "${dpart}" ]]; then
      echo "Selected DATA disk ${ddisk} already carries LABEL=OURBOX_DATA on ${dpart}."
      echo "The SYSTEM disk label must be cleared now to avoid duplicate DATA labels."
    else
      echo "Selected DATA disk ${ddisk} will be initialized as the new DATA disk after ${sys_disk} is cleared."
    fi
    prompt_confirm_exact "REPURPOSE-SYSTEM-DISK" "Type REPURPOSE-SYSTEM-DISK to continue:"
    log "Clearing DATA label from selected SYSTEM disk: ${sys_disk}"
    matchbox_wipe_disk_to_blank_state "${sys_disk}"
    sys_data_part=""
  fi

  if [[ -n "${dpart}" ]]; then
    dpart="$(readlink -f "${dpart}")"
    fstype="$(lsblk -no FSTYPE "${dpart}" 2>/dev/null || true)"
    [[ "${fstype}" == "ext4" ]] || die "selected DATA disk ${dpart} has LABEL=OURBOX_DATA but FSTYPE=${fstype:-unknown}; expected ext4"
  else
    echo
    echo "Selected DATA disk ${ddisk} does not currently carry LABEL=OURBOX_DATA."
    echo "It will be erased and initialized as a fresh DATA disk."
    matchbox_init_data_disk_ext4_labeled "${ddisk}" 1
    dpart="$(readlink -f "${ddisk}p1")"
  fi

  matchbox_require_unmounted_disk "${ddisk}"
  if ! matchbox_inspect_data_partition "${dpart}"; then
    die "could not inspect DATA partition contents (${dpart}); refusing to proceed"
  fi

  if [[ "${MATCHBOX_DATA_HAS_CONTENT}" -eq 1 ]]; then
    echo
    echo "=================================================================="
    echo "DATA disk is NOT empty"
    echo "=================================================================="
    echo
    echo "DATA partition: ${dpart}"
    echo "DATA disk     : ${ddisk}"
    [[ -n "${MATCHBOX_DATA_DEVICE_ID}" ]] && echo "device_id     : ${MATCHBOX_DATA_DEVICE_ID}"
    [[ -n "${MATCHBOX_DATA_BOOTSTRAP_DONE_TS}" ]] && echo "bootstrap.done: ${MATCHBOX_DATA_BOOTSTRAP_DONE_TS}"
    echo

    if [[ "${MATCHBOX_DATA_BOOTSTRAP_DONE}" -eq 1 ]]; then
      echo "This DATA disk was previously bootstrapped."
      echo "KEEP-DATA preserves the current DATA contents."
      echo "Bootstrap will re-run automatically on next boot if the shipped contract changed."
      echo
      echo "Recommended: RESET-BOOTSTRAP when preserving DATA across a SYSTEM reflash."
    else
      echo "This DATA disk contains files, but has no bootstrap.done marker."
      echo "Bootstrapping may overwrite or conflict with existing contents."
      echo
      echo "Recommended: ERASE-DATA (fresh start)."
    fi

    echo
    echo "Choose one:"
    echo "  RESET-BOOTSTRAP  (preserve DATA and force bootstrap on next boot)"
    echo "  ERASE-DATA       (DESTROYS the entire DATA disk and recreates LABEL=OURBOX_DATA)"
    echo "  KEEP-DATA        (preserve DATA; bootstrap reruns only if shipped contract changed)"
    echo

    read -r -p "Type RESET-BOOTSTRAP, ERASE-DATA, or KEEP-DATA: " data_choice
    case "${data_choice}" in
      RESET-BOOTSTRAP)
        matchbox_reset_data_bootstrap_marker "${dpart}"
        ;;
      ERASE-DATA)
        matchbox_init_data_disk_ext4_labeled "${ddisk}" 0
        dpart="$(readlink -f "${ddisk}p1")"
        ;;
      KEEP-DATA)
        log "Keeping DATA disk untouched (operator chose KEEP-DATA)."
        log "Bootstrap will re-run automatically only if the shipped contract state changed."
        ;;
      *)
        die "invalid DATA action"
        ;;
    esac
  fi

  # shellcheck disable=SC2034  # outputs consumed by callers after sourcing this helper
  MATCHBOX_SYSTEM_DISK="${sys_disk}"
  # shellcheck disable=SC2034  # outputs consumed by callers after sourcing this helper
  MATCHBOX_DATA_DISK="${ddisk}"
  # shellcheck disable=SC2034  # outputs consumed by callers after sourcing this helper
  MATCHBOX_DATA_PART="${dpart}"
}
