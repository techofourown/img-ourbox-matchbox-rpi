# OurBox Mini host contracts

This repo produces an OS image that guarantees a small set of contracts. These contracts are the
interface between “image build” and “k8s/apps”.

## Contract: Release metadata

### File

- `/etc/ourbox/release`

### Format

Line-oriented `KEY=VALUE` pairs (shell-friendly). Example keys:

- `OURBOX_PRODUCT`
- `OURBOX_DEVICE`
- `OURBOX_TARGET`
- `OURBOX_SKU`
- `OURBOX_VARIANT`
- `OURBOX_VERSION`
- `OURBOX_RECIPE_GIT_HASH` (recommended)

### Why it exists

- debugging (“what build is on this device?”)
- fleet management (“what should this be running?”)
- predictable support (“we can reproduce your image”)

## Contract: Storage (DATA NVMe)

### Rule

- The DATA drive is **ext4** with filesystem label: `OURBOX_DATA`
- It mounts at: `/var/lib/ourbox`

### Implementation

`/etc/fstab` includes a label-based mount, typically:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

Key properties:

* uses **LABEL** (not `/dev/nvme0n1p1`) to survive device enumeration changes
* uses `nofail` so the system can boot without the data disk
* uses a short systemd timeout to avoid slow boots

### Intended contents of `/var/lib/ourbox`

This is where higher-level stacks should store persistent state:

* k3s storage / persistent volumes
* application state
* logs (if desired)

(Exact directory layout is owned by the k8s/apps layer.)

## Contract: SSD hygiene

* `fstrim.timer` is enabled so periodic TRIM runs automatically.

Verify:

```bash
systemctl status fstrim.timer --no-pager
```

## Non-contracts (explicitly not guaranteed)

* No guarantee that Wi‑Fi is configured on first boot
* No guarantee that Kubernetes is installed (belongs to the next layer)
* No guarantee that the DATA disk is formatted automatically (we expect it to be labeled upfront)

## Related ADRs

* ADR-0002: Storage contract (mount data by label)
* ADR-0003: OS artifact distribution via OCI registry
