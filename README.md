# img-ourbox-mini-rpi

Build repository for **OurBox Mini** OS images targeting **Raspberry Pi hardware** (Pi 5 + dual NVMe).

This repo is responsible for:

- Producing a bootable OS image (via upstream `pi-gen`)
- Enforcing the **OurBox Mini host contracts** (release metadata + storage contract)
- Publishing the OS image as a **registry-hosted artifact** (OCI image containing `os.img.xz`)
- Providing the scripts (“glue”) that make builds repeatable across Docker / nerdctl / podman

If you’re looking for Kubernetes manifests or app code: that lives in a separate repo. This repo ends
at “device boots into a known-good host OS, with `/var/lib/ourbox` mounted”.

## Docs

Start here:

- **Docs index:** [`docs/README.md`](./docs/README.md)
- **Quickstart:** [`docs/guides/01-quickstart.md`](./docs/guides/01-quickstart.md)
- **Build guide:** [`docs/guides/02-build-image.md`](./docs/guides/02-build-image.md)
- **Flash guide (SYSTEM vs DATA NVMe):** [`docs/guides/04-flash-system-nvme.md`](./docs/guides/04-flash-system-nvme.md)
- **Contracts reference:** [`docs/reference/contracts.md`](./docs/reference/contracts.md)

## Golden Path (registry-first)

This is the most repeatable path when you have an internal registry.

### 0) Clone with the pi-gen submodule

```bash
git clone --recurse-submodules <THIS_REPO_URL>
cd img-ourbox-mini-rpi

# If you already cloned without submodules:
git submodule update --init --recursive
```

### 1) (Optional) Mirror dependencies into your registry (one-time)

If your build host can reach DockerHub and you want future builds to be reproducible/offline-friendly:

```bash
./tools/mirror-required-images.sh
```

### 2) Build the OS image

Typical dev build:

```bash
OURBOX_VARIANT=dev OURBOX_VERSION=dev ./tools/build-image.sh
```

Notes:

* The build runs `pi-gen` inside a container, using the container CLI detected on the host
  (`nerdctl` → `docker` → `podman`).
* If using `nerdctl`, the tooling will ensure `buildkitd` is running.
* If you see `pigen_work already exists`, see the runbook:
  [`docs/runbooks/clean-build-environment.md`](./docs/runbooks/clean-build-environment.md)

### 3) Publish the OS artifact to the registry

After a successful build, the output will be in `deploy/`.

Publish it:

```bash
./tools/publish-os-artifact.sh deploy
```

This pushes an OCI image that contains:

* `/artifact/os.img.xz`
* `/artifact/os.info`
* `/artifact/build.log`

### 4) Pull + extract the artifact on any machine

```bash
./tools/pull-os-artifact.sh <registry-image-ref> ./deploy-from-registry
ls -lah ./deploy-from-registry
```

You should see `os.img.xz` and friends.

### 5) Flash to the SYSTEM NVMe (DESTRUCTIVE)

On the Raspberry Pi (or the host doing the flashing), follow:

* [`docs/guides/04-flash-system-nvme.md`](./docs/guides/04-flash-system-nvme.md)

This step **must not** touch the DATA NVMe (labeled `OURBOX_DATA`).

---

## What the image guarantees (contracts)

This repo bakes in two key “host contracts”:

1. **Release metadata** at:

* `/etc/ourbox/release` (simple `KEY=VALUE` lines; includes SKU/variant/version/etc.)

2. **Storage contract**:

* The DATA SSD is an ext4 filesystem labeled **`OURBOX_DATA`**
* It mounts at **`/var/lib/ourbox`** via `/etc/fstab`
* Mount is resilient (uses `nofail` + short device timeout) so the system can boot even if the data
  drive is missing

Details: [`docs/reference/contracts.md`](./docs/reference/contracts.md)

---

## Repository layout

* `vendor/pi-gen/`
  Upstream `pi-gen` as a submodule (arm64 branch). This is the image builder.

* `pigen/`
  OurBox customization:

  * `pigen/config/ourbox.conf` (pi-gen config)
  * `pigen/stages/stage-ourbox-mini/` (OurBox Mini steps)
  * `pigen/overrides/` (override upstream behavior)

* `tools/`
  Operational scripts:

  * `registry.sh`: registry config + helper functions
  * `mirror-required-images.sh`: optional image mirroring into your registry
  * `pull-required-images.sh`: pulls from your registry and tags to expected names
  * `build-image.sh`: builds the OS image
  * `publish-os-artifact.sh`: wraps build output into an OCI artifact image
  * `pull-os-artifact.sh`: pulls artifact image and extracts `/artifact/*`

* `docs/`
  Guides, reference docs, runbooks, troubleshooting, plus RFC/ADR history.

---

## Releases / versioning

This repo uses `semantic-release` (see `.releaserc.cjs`) to maintain:

* Git tags like `vX.Y.Z`
* `CHANGELOG.md`
* GitHub release notes (via workflow)

Release runbook:
[`docs/runbooks/release-process.md`](./docs/runbooks/release-process.md)

> Note: publishing the OS artifact into your registry is currently a **separate step** from a GitHub
> release. In practice, we treat “registry artifact published + device boot verified” as the true
> release of an OS build.

---

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).

Key rule: **Do not commit build artifacts** (`deploy/`, `*.img.xz`, etc.). They belong in the registry
or as ad-hoc transfers (SCP/USB).
