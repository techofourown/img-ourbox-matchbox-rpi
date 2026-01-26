# Flash the SYSTEM NVMe safely (protect the DATA NVMe)

This is the most dangerous step. We have two NVMe drives:

- **DATA**: ext4, labeled `OURBOX_DATA` (must not be wiped)
- **SYSTEM**: raw disk target we will overwrite (will be wiped)

## Prerequisites

- `os.img.xz` present locally on the machine doing the flash (often the Pi)
- `xz`, `dd`, `lsblk`, `readlink`

## 1) Confirm current root is NOT the SYSTEM disk you will overwrite

```bash
findmnt /
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

If you are booted from SD/USB, `/` should show `mmcblk*` or `sd*`.

## 2) Identify DATA and SYSTEM deterministically

DATA should be found by label:

```bash
ls -l /dev/disk/by-label/OURBOX_DATA
```

SYSTEM should be referenced by `by-id` (serial):

```bash
ls -l /dev/disk/by-id/ | grep -i nvme || true
```

## 3) Safety rails script (recommended)

This verifies the DATA disk and SYSTEM disk are different before flashing.

```bash
set -euo pipefail

IMG="/root/os.img.xz"

# DATA (already correct; do NOT wipe)
DATA_PART="/dev/disk/by-label/OURBOX_DATA"

# SYSTEM disk target (flash THIS) - set to your by-id
SYS_DISK="/dev/disk/by-id/<YOUR_SYSTEM_NVME_BY_ID>"

DATA_DEV="$(readlink -f "$DATA_PART")"
DATA_DISK="/dev/$(lsblk -no PKNAME "$DATA_DEV")"
SYS_DEV="$(readlink -f "$SYS_DISK")"

echo "IMG=$IMG"
echo "DATA_PART=$DATA_PART -> $DATA_DEV (disk $DATA_DISK)"
echo "SYS_DISK=$SYS_DISK -> $SYS_DEV"
echo

echo "=== DATA disk (must keep) ==="
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$DATA_DISK"
echo
echo "=== SYSTEM disk (will be erased) ==="
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$SYS_DEV"
echo

if [ "$SYS_DEV" = "$DATA_DISK" ]; then
  echo "ERROR: SYS_DEV resolves to DATA disk ($DATA_DISK). Refusing." >&2
  exit 1
fi

echo "About to ERASE and flash: $SYS_DEV"
read -r -p "Type FLASH (all caps) to continue: " ans
[ "$ans" = "FLASH" ]

echo "Flashing now..."
xzcat "$IMG" | dd of="$SYS_DEV" bs=4M conv=fsync status=progress
sync
```

## 4) Confirm the partition layout after flashing

```bash
partprobe "$SYS_DEV" || true
lsblk -f "$SYS_DEV"
```

Expected:

* a small FAT partition (boot)
* an ext4 partition (root)

## 5) Boot transition

* Power down
* Remove SD card (or adjust boot order so NVMe boots first)
* Boot into the new OS

Verify:

```bash
findmnt /
```

You should see `/` from the NVMe root partition.

## 6) Confirm the DATA mount contract

```bash
findmnt /var/lib/ourbox || true
grep -n 'OURBOX_DATA' /etc/fstab
```

Details: `docs/reference/contracts.md`
