#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd lsblk
need_cmd readlink
need_cmd sed
need_cmd awk
need_cmd git

SUDO=""
if [[ ${EUID} -ne 0 ]]; then
  need_cmd sudo
  SUDO="sudo -E"
fi

REGISTRY_ROUNDTRIP=0
if [[ "${1:-}" == "--registry-roundtrip" ]]; then
  REGISTRY_ROUNDTRIP=1
  shift
fi
if [[ $# -ne 0 ]]; then
  die "Usage: $0 [--registry-roundtrip]"
fi

banner() {
  echo
  echo "=================================================================="
  echo "OurBox Mini OS — End-to-end build + flash (interactive, destructive)"
  echo "=================================================================="
  echo
}

prompt_confirm_exact() {
  local expected="$1"
  local prompt="$2"
  local ans=""
  read -r -p "${prompt} " ans
  [[ "${ans}" == "${expected}" ]] || die "confirmation did not match (expected: ${expected})"
}

prompt_nonempty() {
  local prompt="$1"
  local default="${2:-}"
  local ans=""
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " ans
    ans="${ans:-${default}}"
  else
    read -r -p "${prompt}: " ans
  fi
  [[ -n "${ans}" ]] || die "value required"
  echo "${ans}"
}

ensure_not_booted_from_nvme() {
  # Robust even when findmnt reports /dev/root.
  if lsblk -nr -o NAME,MOUNTPOINT \
    | awk '$2=="/" && $1 ~ /^nvme/ {exit 0} END{exit 1}'; then
    die "root filesystem is on an NVMe device. Boot from SD/USB before flashing NVMe."
  fi
}

nvme_disks() {
  # Returns /dev/nvme0n1 style disk paths (type=disk)
  lsblk -dn -o NAME,TYPE \
    | awk '$2=="disk" && $1 ~ /^nvme[0-9]+n[0-9]+$/ {print "/dev/"$1}'
}

show_nvme_summary() {
  local disks=("$@")
  echo
  echo "NVMe disks detected:"
  echo
  # Show disks and partitions
  lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${disks[@]}" || true
  echo
}

data_part_by_label() {
  if [[ -e /dev/disk/by-label/OURBOX_DATA ]]; then
    readlink -f /dev/disk/by-label/OURBOX_DATA
  else
    echo ""
  fi
}

parent_disk_of_part() {
  local part="$1"
  echo "/dev/$(lsblk -no PKNAME "${part}")"
}

unmount_anything_on_disk() {
  local disk="$1"
  # Unmount any mounted partitions on this disk (best-effort).
  while read -r name mp; do
    [[ -n "${mp}" ]] || continue
    log "Unmounting ${mp} (/dev/${name})"
    ${SUDO} umount "/dev/${name}" >/dev/null 2>&1 || ${SUDO} umount "${mp}" >/dev/null 2>&1 || true
  done < <(lsblk -nr -o NAME,MOUNTPOINT "${disk}" | awk 'NF==2 && $2!="" {print $1, $2}')
}

init_data_disk_ext4_labeled() {
  local disk="$1"

  need_cmd parted
  need_cmd mkfs.ext4
  need_cmd partprobe
  need_cmd wipefs

  log "About to DESTROY and initialize DATA disk: ${disk}"
  unmount_anything_on_disk "${disk}"

  echo
  show_nvme_summary "${disk}"
  echo "This will erase EVERYTHING on ${disk} and create a single ext4 partition labeled OURBOX_DATA."
  prompt_confirm_exact "ERASE-DATA" "Type ERASE-DATA to continue:"

  ${SUDO} wipefs -a "${disk}" || true
  ${SUDO} parted -s "${disk}" mklabel gpt
  ${SUDO} parted -s "${disk}" mkpart primary ext4 1MiB 100%
  ${SUDO} partprobe "${disk}" || true

  local part="${disk}p1"
  ${SUDO} mkfs.ext4 -F -L OURBOX_DATA "${part}"

  log "DATA disk initialized: ${part} (LABEL=OURBOX_DATA)"
  echo
}

pick_other_disk() {
  local a="$1" b="$2" chosen="$3"
  if [[ "${chosen}" == "${a}" ]]; then
    echo "${b}"
  else
    echo "${a}"
  fi
}

pick_data_disk_if_missing() {
  local disks=("$@")
  local dpart
  dpart="$(data_part_by_label)"
  if [[ -n "${dpart}" ]]; then
    echo ""  # no need to pick
    return 0
  fi

  echo
  echo "No filesystem labeled OURBOX_DATA was found."
  echo "We can initialize one NVMe disk as DATA (ext4, LABEL=OURBOX_DATA)."
  echo "You must choose which NVMe disk becomes DATA."
  echo

  show_nvme_summary "${disks[@]}"

  echo "Choose the DATA disk:"
  echo "  1) ${disks[0]}"
  echo "  2) ${disks[1]}"
  local choice=""
  read -r -p "Enter 1 or 2: " choice
  [[ "${choice}" == "1" || "${choice}" == "2" ]] || die "invalid choice"

  if [[ "${choice}" == "1" ]]; then
    echo "${disks[0]}"
  else
    echo "${disks[1]}"
  fi
}

byid_for_disk() {
  local disk="$1"
  local best=""

  # Prefer nvme-eui.* if present, otherwise first matching by-id symlink.
  for p in /dev/disk/by-id/*; do
    [[ -L "${p}" ]] || continue
    [[ "${p}" == *-part* ]] && continue
    local target
    target="$(readlink -f "${p}" 2>/dev/null || true)"
    [[ "${target}" == "${disk}" ]] || continue

    local base
    base="$(basename "${p}")"
    if [[ "${base}" == nvme-eui.* ]]; then
      echo "${p}"
      return 0
    fi
    [[ -z "${best}" ]] && best="${p}"
  done

  [[ -n "${best}" ]] || return 1
  echo "${best}"
}

newest_img_xz() {
  local img=""
  img="$(ls -1t "${ROOT}/deploy"/img-*.img.xz 2>/dev/null | head -n 1 || true)"
  [[ -n "${img}" && -f "${img}" ]] || die "no deploy/img-*.img.xz found; build likely failed"
  echo "${img}"
}

compute_os_artifact_ref_from_img() {
  local img="$1"
  local base
  base="$(basename "${img}" .img.xz)"
  echo "$(imgref os "${base}")"
}

main() {
  banner

  ensure_not_booted_from_nvme

  log "Ensuring submodules are present"
  (cd "${ROOT}" && git submodule update --init --recursive)

  log "Bootstrapping host dependencies (Podman + BuildKit + basics)"
  "${ROOT}/tools/bootstrap-host.sh"

  # Prefer podman automatically (registry.sh now defaults to sudo podman when needed)
  export DOCKER="${DOCKER:-$(pick_container_cli)}"
  log "Using container CLI: ${DOCKER}"

  # Common after a failed pi-gen run: container name collision.
  # Offer to clean it up so reruns are reliable.
  if $DOCKER ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'pigen_work'; then
    log "Found existing container: pigen_work (likely from a previous failed build)"
    prompt_confirm_exact "CLEAN" "Type CLEAN to remove pigen_work and continue:"
    $DOCKER rm -f -v pigen_work >/dev/null 2>&1 || true
  fi

  # Enforce pinned versions
  [[ -n "${K3S_VERSION:-}" ]] || die "K3S_VERSION not set; check tools/versions.env"
  [[ -n "${NGINX_IMAGE:-}" ]] || die "NGINX_IMAGE not set; check tools/versions.env"
  log "Pinned versions: K3S_VERSION=${K3S_VERSION} NGINX_IMAGE=${NGINX_IMAGE}"

  log "Fetching airgap artifacts"
  "${ROOT}/tools/fetch-airgap-platform.sh"

  : "${OURBOX_VARIANT:=dev}"
  : "${OURBOX_VERSION:=dev}"

  log "Building OS image (OURBOX_VARIANT=${OURBOX_VARIANT} OURBOX_VERSION=${OURBOX_VERSION})"
  OURBOX_VARIANT="${OURBOX_VARIANT}" OURBOX_VERSION="${OURBOX_VERSION}" "${ROOT}/tools/build-image.sh"

  local img_xz
  img_xz="$(newest_img_xz)"
  log "Built image: ${img_xz}"
  xz -t "${img_xz}"

  local flash_img="${img_xz}"

  if [[ "${REGISTRY_ROUNDTRIP}" == "1" ]]; then
    log "Registry round-trip requested: publish + pull (no manual copy/paste)"
    "${ROOT}/tools/publish-os-artifact.sh" "${ROOT}/deploy"
    rm -rf "${ROOT}/deploy-from-registry" || true
    "${ROOT}/tools/pull-os-artifact.sh" --latest "${ROOT}/deploy-from-registry"
    xz -t "${ROOT}/deploy-from-registry/os.img.xz"
    flash_img="${ROOT}/deploy-from-registry/os.img.xz"
    log "Using pulled artifact for flashing: ${flash_img}"
  fi

  # NVMe safety: exactly two NVMe disks
  mapfile -t disks < <(nvme_disks)
  if [[ "${#disks[@]}" -ne 2 ]]; then
    echo
    lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS || true
    echo
    die "expected exactly 2 NVMe disks; found ${#disks[@]}. Disconnect extra NVMe devices and retry."
  fi

  show_nvme_summary "${disks[@]}"

  # Ensure DATA disk exists (or initialize it)
  local dpart ddisk data_disk_choice
  dpart="$(data_part_by_label)"
  if [[ -z "${dpart}" ]]; then
    data_disk_choice="$(pick_data_disk_if_missing "${disks[@]}")"
    init_data_disk_ext4_labeled "${data_disk_choice}"
    dpart="$(data_part_by_label)"
    [[ -n "${dpart}" ]] || die "failed to create OURBOX_DATA label"
  fi

  ddisk="$(parent_disk_of_part "${dpart}")"
  if [[ "${ddisk}" != /dev/nvme* ]]; then
    die "OURBOX_DATA label is not on an NVMe disk (${ddisk}); refusing for safety"
  fi
  local fstype
  fstype="$(lsblk -no FSTYPE "${dpart}" 2>/dev/null || true)"
  if [[ "${fstype}" != "ext4" ]]; then
    die "DATA disk ${dpart} has LABEL=OURBOX_DATA but FSTYPE=${fstype:-unknown}. Contract requires ext4."
  fi

  # SYSTEM disk is the other NVMe disk
  local sys_disk
  sys_disk="$(pick_other_disk "${disks[0]}" "${disks[1]}" "${ddisk}")"

  echo
  log "Disk selection:"
  log "  DATA   : ${ddisk} (partition ${dpart} LABEL=OURBOX_DATA)"
  log "  SYSTEM : ${sys_disk} (will be wiped)"

  echo
  show_nvme_summary "${ddisk}" "${sys_disk}"

  echo "WARNING: This will ERASE and overwrite the SYSTEM disk: ${sys_disk}"
  prompt_confirm_exact "${sys_disk}" "To confirm, type the SYSTEM disk path exactly:"

  # Prefer by-id for flashing (flash script accepts raw NVMe too, but by-id is best)
  local sys_byid=""
  if sys_byid="$(byid_for_disk "${sys_disk}")"; then
    log "SYSTEM by-id: ${sys_byid}"
  else
    log "WARNING: could not find /dev/disk/by-id symlink for ${sys_disk}; flashing will use the raw device path"
    sys_byid="${sys_disk}"
  fi

  # Unmount anything on SYSTEM (best-effort)
  unmount_anything_on_disk "${sys_disk}"

  log "Flashing SYSTEM NVMe"
  "${ROOT}/tools/flash-system-nvme.sh" "${flash_img}" "${sys_byid}" || die "flash failed; refusing to continue"

  echo
  local default_user="${SUDO_USER:-$(whoami)}"
  local new_user
  new_user="$(prompt_nonempty "Username for first boot" "${default_user}")"

  log "Writing userconf.txt to boot partition (will prompt for password)"
  "${ROOT}/tools/preboot-userconf.sh" "${sys_disk}" "${new_user}"

  echo
  echo "DONE."
  echo
  echo "Next steps:"
  echo "  - Power down"
  echo "  - Remove SD/USB (or fix boot order)"
  echo "  - Boot from NVMe SYSTEM"
  echo
  echo "After first boot, verify:"
  echo "  findmnt /"
  echo "  findmnt /var/lib/ourbox"
  echo "  systemctl status k3s --no-pager || true"
  echo "  sudo /usr/local/bin/k3s kubectl get pods -A"
  echo "  curl -sSf http://127.0.0.1:30080 | head"
  echo
}

main
