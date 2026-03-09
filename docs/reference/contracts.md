# OurBox Matchbox host contracts

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
- `OURBOX_PLATFORM_CONTRACT_SOURCE` (required — see below)
- `OURBOX_PLATFORM_CONTRACT_REVISION` (required — see below)
- `OURBOX_PLATFORM_CONTRACT_VERSION` (optional, when known)
- `OURBOX_PLATFORM_CONTRACT_CREATED` (optional, when known)
- `OURBOX_PLATFORM_CONTRACT_DIGEST` (optional, when OCI packaging exists)
- `OURBOX_INSTALLER_ID`
- `OURBOX_INSTALLER_VERSION`
- `OURBOX_INSTALLER_GIT_HASH`
- `OURBOX_OS_ARTIFACT_SOURCE`
- `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`
- `OURBOX_OS_IMAGE_SHA256`
- `OURBOX_INSTALL_DEFAULTS_SOURCE`
- `OURBOX_INSTALL_DEFAULTS_REF`
- `OURBOX_INSTALL_SELECTION_SOURCE`
- `OURBOX_RELEASE_CHANNEL`

### Platform contract provenance (normative)

Matchbox images MUST record the upstream OurBox OS platform contract provenance so operators can
answer:

- "Which platform baseline did this image ship?"
- "What upstream revision/digest does it correspond to?"

Minimum requirement (Phase 0+):
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`

When available, prefer also recording:
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`

See `docs/reference/platform-contract.md` for the full provenance model and artifact workflow.

### Why it exists

- debugging (“what build is on this device?”)
- fleet management (“what should this be running?”)
- predictable support (“we can reproduce your image”)

## Contract: Storage (DATA NVMe)

### Rule

- The DATA drive is **ext4** with filesystem label: `OURBOX_DATA`
- It mounts at: `/var/lib/ourbox`
- Either physical NVMe may serve as DATA on a given install; the role is determined by the label, not by a permanently reserved slot

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
* k3s is part of the OS image (as the “platform runtime”), but application manifests live elsewhere
* The OS includes `ourbox-bootstrap.service` which brings up k3s and applies baseline manifests
* If k3s can’t start because the kernel lacks the memory cgroup controller, the remedy is the
  cmdline flags (see [`docs/OPS.md`](../OPS.md) troubleshooting)
* No guarantee that the DATA disk is formatted automatically (we expect it to be labeled upfront)

## Contract: Installer media contract

Installer media contains the runtime installer and fetches the OS payload at install time.

- Entrypoint: `/opt/ourbox/tools/ourbox-install`
- Shared resolver policy: `/opt/ourbox/tools/installer-selection-resolver.sh`
- Shared installer SSH policy helper: `/opt/ourbox/tools/installer-ssh-helper.sh`
- Defaults: `/opt/ourbox/installer/defaults.env`
- Optional override (on boot media, for runtime payload-selection controls): `/boot/firmware/ourbox-installer.env`
- Payload/cache path: `/opt/ourbox/installer/cache/payload`
- Required payload artifact files (oras pull):
  - `os.img.xz`
  - `os.img.xz.sha256` (required; must match content)
  - `os.meta.env` (KEY=VALUE metadata: target/variant/version/sku/git_sha/k3s/platform contract digest)
  - optional: `os.info`, `build.log`
- Optional catalog artifact `${OS_TARGET}-catalog` with `catalog.tsv` for interactive version selection.
- After flashing, installer-selected payload provenance is appended directly to `/etc/ourbox/release`
  on the installed root filesystem.
- Installer SSH policy is baked at image-build time and realized through the upstream installer SSH
  contract. Boot-media runtime overrides do not apply to `OURBOX_INSTALLER_SSH_*` knobs.
- Official/public Matchbox media uses `OURBOX_INSTALLER_SSH_MODE=off`.
- SSH-enabled support/lab media is explicit opt-in only and must provide build-time auth material.

## Contract: Platform runtime (k3s)

* `k3s` binary exists at `/usr/local/bin/k3s`
* `k3s.service` exists and is enabled by bootstrap (or enabled directly)
* `ourbox-bootstrap.service` exists and runs at boot
* bootstrap skips reapply only when the stored applied contract state still matches the shipped contract
* Success marker: `/var/lib/ourbox/state/bootstrap.done`
* k3s data lives under `/var/lib/ourbox/k3s`

## Contract: Kernel cmdline must enable cgroup memory

If `/sys/fs/cgroup/cgroup.controllers` does not include `memory`, k3s will fail with
`failed to find memory cgroup (v2)`.

Fix: add `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1` to
`/boot/firmware/cmdline.txt`. See [`docs/OPS.md`](../OPS.md) for the full procedure.

Long-term intent: bake this into the image during build.

## Related ADRs

* ADR-0002: Storage contract (mount data by label)
* ADR-0003: OS artifact distribution via OCI registry
* ADR-0004: Consume platform contract from `sw-ourbox-os` (provenance + allocation)
