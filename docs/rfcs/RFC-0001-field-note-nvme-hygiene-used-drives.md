# RFC-0001: Field Note - NVMe Hygiene for Used Drives (OurBox Mini)

**Status:** Draft (Non-normative field note)  
**Created:** 2026-01-19  
**Updated:** 2026-01-19

---

## What

This memo documents a one-time procedure used to **sanitize, health-check, and prepare** two
**used/unknown-state NVMe SSDs** installed in an OurBox Mini (Raspberry Pi 5 + dual NVMe HAT).

This is **not a normative spec** and is **not required** for production flows. It exists so that
anyone in a similar situation (e.g., used drives, unknown provenance, "it was in a drawer") can
reproduce a clean baseline safely.

> Production units should generally use **new, known-good storage** and a defined manufacturing
> process. This note is primarily for developer hardware and recovery/bring-up scenarios.

---

## Why

Used drives can arrive in an unknown state:

- Leftover partition tables or filesystem signatures can cause confusing behavior.
- "Looks blank" is not the same as "is safe to use."
- For an appliance, we want a stable storage contract so first-boot automation can be safe.

Goals:

1. Confirm the drives are healthy enough for dev use (SMART / media errors).
2. Ensure **no stale partition/filesystem metadata** remains (clean slate).
3. Prepare a **data drive** with a deterministic identity (filesystem LABEL), so automation can
   mount it reliably without relying on `nvme0`/`nvme1` enumeration.
4. Enable basic ongoing SSD hygiene (TRIM).

---

## Preconditions / Safety

- Boot from a disk that is **NOT** one of the NVMe drives you are sanitizing  
  (e.g., SD card / "rescue OS" / USB SSD).
- Verify **nothing from NVMe is mounted**.
- Expect all wipe/format steps to be **destructive** (data loss).
- Do not trust `nvme0` vs `nvme1` ordering. Use **serial numbers** to identify devices.

---

## Procedure

### 1) Confirm nothing NVMe is mounted

```bash
mount | grep nvme || echo "No NVMe mounts (good)."
lsblk -f
```

### 2) Inspect existing signatures and partition tables (non-destructive)

```bash
# Signatures (GPT/ext4/LUKS/etc.) if any:
wipefs -n /dev/nvme0n1
wipefs -n /dev/nvme1n1

# Partition tables if any:
fdisk -l /dev/nvme0n1
fdisk -l /dev/nvme1n1

# Capture stable identifiers (serials):
lsblk -d -o NAME,SIZE,MODEL,SERIAL
```

### 3) Install tooling (Debian/Raspberry Pi OS)

```bash
sudo apt update
sudo apt install -y nvme-cli smartmontools gdisk
```

Then:

```bash
nvme list
```

### 4) Health check (used drives)

Quick SMART log:

```bash
nvme smart-log /dev/nvme0
nvme smart-log /dev/nvme1
```

More verbose:

```bash
smartctl -a /dev/nvme0
smartctl -a /dev/nvme1
```

What we cared about:

- `critical_warning: 0`
- `media_errors: 0`
- `unsafe_shutdowns: 0`
- `percentage_used`: nonzero is expected for used drives; acceptable for dev depends on comfort.  
  (In our case: ~21% and ~31%.)

### 5) Assign roles: SYSTEM vs DATA

We recommend explicitly choosing:

- **SYSTEM disk**: the disk that will later be flashed with the pi-gen OS image.
- **DATA disk**: a disk/partition used for `/var/lib/ourbox` (k3s PVs, app data, etc.).

If one drive is "better" (lower wear / `percentage_used`), prefer that for **DATA**, since it will
typically see more sustained writes over time.

Record the chosen mapping by **serial number** in your build notes.

### 6) Sanitize both disks (destructive)

This wipes partition tables and filesystem signatures:

```bash
# Example: sanitize SYSTEM disk
sudo sgdisk --zap-all /dev/nvme1n1
sudo wipefs -a /dev/nvme1n1

# Example: sanitize DATA disk
sudo sgdisk --zap-all /dev/nvme0n1
sudo wipefs -a /dev/nvme0n1
```

Optional: full-device discard (TRIM everything). This may fail on some setups; it is not required.

```bash
sudo blkdiscard -f /dev/nvme1n1 || true
sudo blkdiscard -f /dev/nvme0n1 || true
```

Verify clean state:

```bash
wipefs -n /dev/nvme0n1
wipefs -n /dev/nvme1n1
lsblk -f
```

### 7) Create the DATA filesystem with a stable LABEL (recommended)

We standardize on an ext4 filesystem labeled:

- `OURBOX_DATA`

Example (data disk is `/dev/nvme0n1`):

```bash
sudo parted /dev/nvme0n1 --script mklabel gpt mkpart primary ext4 1MiB 100%
sudo mkfs.ext4 -F -L OURBOX_DATA /dev/nvme0n1p1
```

Verify:

```bash
lsblk -f /dev/nvme0n1
# Expect: nvme0n1p1 ext4 LABEL=OURBOX_DATA
```

> Note: We intentionally did **not** mount the data disk on the current SD-based system.
> The pi-gen image / first-boot provisioning should handle mounting by LABEL as part of the appliance contract.

### 8) Enable periodic TRIM (SSD hygiene)

```bash
sudo systemctl enable --now fstrim.timer
sudo systemctl status fstrim.timer --no-pager
```

---

## Result / Postconditions

After this procedure, you should have:

- One NVMe left **blank** (no partitions): this will be the future **SYSTEM** flash target.
- One NVMe containing exactly one ext4 partition:

  - `LABEL=OURBOX_DATA`
  - not mounted automatically (until the appliance image mounts it)

This sets up a clean foundation for pi-gen + first-boot automation to:

- mount data by label (`/dev/disk/by-label/OURBOX_DATA`) instead of relying on enumeration order
- safely initialize higher-level services (k3s, containerd storage, PVs)

---

## Trade-offs / Notes

- `blkdiscard` is convenient but not always supported; `sgdisk --zap-all` + `wipefs -a` is usually sufficient.
- "Secure erase" can mean different things depending on threat model; this memo prioritizes
  operational cleanliness over formal sanitization guarantees.
- Used drives with meaningful wear are fine for dev, but should not be assumed acceptable for
  shipping units without a policy.

---

## Open Questions (future work)

- Should we define a formal manufacturing/storage sanitization policy for production?
- Should `OURBOX_DATA` label be codified as a formal contract (ADR) once the image pipeline is in place?
- Should first-boot provisioning support detecting and initializing an unformatted second NVMe safely?

---

## References

- `docs/decisions/ADR-0001-adopt-rpi-os-lite.md` (base OS choice; image pipeline context)
- `man nvme`
- `man smartctl`
- `man wipefs`
- `man sgdisk`
- `man blkdiscard`
- `man fstrim`

