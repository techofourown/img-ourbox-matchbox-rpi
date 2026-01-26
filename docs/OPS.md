# OurBox Mini OS — Operator Runbook (Build → Publish → Flash → Boot)

**Last verified:** 2026-01-26  
**Verified on:** Pi 5 + dual NVMe (DATA label `OURBOX_DATA`, SYSTEM flashed to other NVMe)  
**Outcome:** k3s + hello workload running, nginx reachable on `127.0.0.1:30080`

This is the only step-by-step doc. If reality and this file disagree, update this file.

---

## What you need

### Build host (e.g. centroid)
- This repo cloned with submodules
- One container CLI: `nerdctl` **or** `docker` **or** `podman`
- Enough disk space for pi-gen output

### Flash host (often the Pi)
- `xz`, `dd`, `lsblk`, `readlink`, `partprobe`
- **Extreme caution**: we have two NVMe drives:
  - **DATA**: ext4 labeled `OURBOX_DATA` (must never be wiped)
  - **SYSTEM**: raw disk that will be overwritten (will be wiped)

---

## 0) Clone correctly (submodules)

```bash
git clone --recurse-submodules <REPO_URL>
cd img-ourbox-mini-rpi

# If you already cloned:
git submodule update --init --recursive
```

---

## 1) Fetch airgap platform artifacts (k3s + images)

This repo builds an image that includes an airgapped k3s. You must fetch the artifacts before building.

### Choose a real k3s tag

Pinning is best. For quick dev you can grab “latest”:

```bash
export K3S_VERSION="$(
  curl -fsSLI https://github.com/k3s-io/k3s/releases/latest \
  | tr -d '\r' \
  | sed -n 's/^location: .*\/tag\/\(v[^ ]*\)$/\1/ip' \
  | tail -n1
)"
echo "K3S_VERSION=$K3S_VERSION"
```

### Choose your container CLI explicitly (recommended)

```bash
export DOCKER="nerdctl"   # or docker, or podman
```

### Fetch artifacts

```bash
./tools/fetch-airgap-platform.sh
```

#### Nerdctl gotcha: arm64 image export

If you see errors like “digest not found” while saving images, it’s almost always a multi-arch/platform mismatch.
The fix pattern is:

```bash
nerdctl pull --platform=linux/arm64 nginx:1.27-alpine
nerdctl save --platform=linux/arm64 -o artifacts/airgap/platform/images/nginx_1.27-alpine.tar nginx:1.27-alpine
```

(Your script should do this correctly; if not, update the script. Don’t “document around” a broken script forever.)

---

## 2) Build the OS image

```bash
OURBOX_VARIANT=dev OURBOX_VERSION=dev ./tools/build-image.sh
```

Expected output: a `deploy/` directory with:

* `img-*.img.xz`
* `*.info`
* `build.log`

### nerdctl gotcha: deploy copy failure

If the build finishes but ends with a nerdctl tar/cp error, manually copy deploy out of the container:

```bash
nerdctl ps -a | egrep 'pigen|pi-gen' || true
mkdir -p deploy
nerdctl cp pigen_work:/pi-gen/deploy/. ./deploy/
ls -lah deploy
```

---

## 3) Publish the OS image as a registry artifact (OCI)

From the build host:

```bash
xz -t deploy/img-*.img.xz
./tools/publish-os-artifact.sh deploy
```

Save the printed image reference, e.g.
`registry.example.dev/ourbox/os:<tag>`

---

## 4) Pull + extract the artifact (any machine with container CLI)

```bash
rm -rf ./deploy-from-registry
./tools/pull-os-artifact.sh <registry-image-ref> ./deploy-from-registry
ls -lah ./deploy-from-registry
xz -t ./deploy-from-registry/os.img.xz
```

---

## 5) Transfer to the Pi (simple + universal)

If the Pi does NOT have this repo + container tooling, just SCP:

```bash
scp ./deploy-from-registry/os.img.xz johnb@<pi-ip>:/home/johnb/os.img.xz
scp ./deploy-from-registry/os.info   johnb@<pi-ip>:/home/johnb/os.info
```

---

## 6) Flash the SYSTEM NVMe (DESTRUCTIVE — protect DATA)

### 6.1 Verify current root is NOT the disk you will overwrite

```bash
findmnt /
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

If you are booted from SD/USB, `/` should be `mmcblk*` or `sd*`, NOT `nvme*`.

### 6.2 Identify DATA by label and SYSTEM by by-id

```bash
ls -l /dev/disk/by-label/OURBOX_DATA
ls -l /dev/disk/by-id/ | grep -i nvme || true
```

### 6.3 Use the safety rails flash script

Copy/paste and ONLY edit `SYS_DISK`:

```bash
set -euo pipefail

IMG="/home/johnb/os.img.xz"
DATA_PART="/dev/disk/by-label/OURBOX_DATA"
SYS_DISK="/dev/disk/by-id/<YOUR_SYSTEM_NVME_BY_ID>"   # MUST be a raw disk by-id (not a partition)

xz -t "$IMG"

DATA_DEV="$(readlink -f "$DATA_PART")"
DATA_DISK="/dev/$(lsblk -no PKNAME "$DATA_DEV")"
SYS_DEV="$(readlink -f "$SYS_DISK")"

echo "IMG=$IMG"
echo "DATA_PART=$DATA_PART -> $DATA_DEV (disk $DATA_DISK)"
echo "SYS_DISK=$SYS_DISK -> $SYS_DEV"
echo

lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$DATA_DISK"
echo
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$SYS_DEV"
echo

if [ "$SYS_DEV" = "$DATA_DISK" ]; then
  echo "ERROR: SYS_DEV resolves to DATA disk ($DATA_DISK). Refusing." >&2
  exit 1
fi

read -r -p "Type FLASH (all caps) to erase and flash $SYS_DEV: " ans
[ "$ans" = "FLASH" ]

xzcat "$IMG" | dd of="$SYS_DEV" bs=4M conv=fsync status=progress
sync

partprobe "$SYS_DEV" || true
lsblk -f "$SYS_DEV"
```

---

## 7) Pre-boot config (set username/password without wizard)

Before booting the newly-flashed NVMe OS, mount the SYSTEM boot partition and create `userconf.txt`.

```bash
set -euo pipefail
SYS_DEV="/dev/nvme1n1"      # example: your SYSTEM disk
BOOT_PART="${SYS_DEV}p1"

sudo mkdir -p /mnt/ourbox-boot
sudo mount "$BOOT_PART" /mnt/ourbox-boot

NEW_USER="johnb"
HASH="$(openssl passwd -6)"   # prompts for password, outputs hash
echo "${NEW_USER}:${HASH}" | sudo tee /mnt/ourbox-boot/userconf.txt >/dev/null

# Optional: enable ssh on first boot (if your base expects /boot/firmware/ssh)
sudo touch /mnt/ourbox-boot/ssh || true

sudo sync
sudo umount /mnt/ourbox-boot
```

Power down, remove SD (or fix boot order), and boot the NVMe OS.

---

## 8) First boot verification (what “good” looks like)

### 8.1 Storage mounts

```bash
findmnt /
findmnt /var/lib/ourbox || true
```

Expected:

* `/` is `nvme...p2`
* `/var/lib/ourbox` is the DATA disk (`LABEL=OURBOX_DATA`)

### 8.2 Bootstrap + k3s

```bash
systemctl status ourbox-bootstrap --no-pager || true
systemctl status k3s --no-pager || true

sudo /usr/local/bin/k3s kubectl get nodes
sudo /usr/local/bin/k3s kubectl get pods -A
```

### 8.3 Demo service reachable

```bash
curl -sSf http://127.0.0.1:30080 | head
```

### 8.4 Bootstrap completion marker

```bash
sudo cat /var/lib/ourbox/state/bootstrap.done 2>/dev/null || true
```

---

## Troubleshooting

### k3s fails with: “failed to find memory cgroup (v2)”

Symptom:

* `systemctl status k3s` shows crash loop
* journal shows: `fatal ... failed to find memory cgroup (v2)`

Fix (on the Pi):

```bash
sudo systemctl stop ourbox-bootstrap.service || true
sudo systemctl stop k3s.service || true
sudo systemctl disable k3s.service || true

sudo cp -a /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
sudo sed -i '1 s/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt
cat /boot/firmware/cmdline.txt

sudo reboot
```

Verify after reboot:

```bash
stat -fc %T /sys/fs/cgroup
cat /sys/fs/cgroup/cgroup.controllers
```

You should see `cgroup2fs` and `memory` present in controllers.

Then:

```bash
sudo systemctl start ourbox-bootstrap.service
sudo systemctl status k3s --no-pager
```

**Important note:** You cannot “fix this on centroid” by running scripts that use `ROOTFS_DIR` unless you are inside the pi-gen build environment. `ROOTFS_DIR` is not set on your host shell.

To fix an already-flashed device, edit `/boot/firmware/cmdline.txt` on the device (or mount the boot partition and edit it there). To bake this into the image, implement it in a pi-gen stage script (code change), not a host shell snippet.

### “Container pigen_work already exists”

```bash
nerdctl rm -v pigen_work || true
# or docker rm -v pigen_work || true
```

### Wi‑Fi blocked by rfkill

```bash
sudo raspi-config
# Localisation Options -> WLAN Country
```

### Registry TLS / unknown CA

Use SCP as a fallback, or install your registry CA. Don’t stall the workflow on this.
