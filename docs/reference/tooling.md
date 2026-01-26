# Tooling reference (tools/ and pigen/)

This document explains the main scripts and how they fit together.

## tools/registry.sh

Responsibilities:

- loads `tools/registry.env` if present
- provides `pick_container_cli` (nerdctl/docker/podman)
- provides registry helper functions (e.g. image refs)
- ensures `buildkitd` when needed (nerdctl)

Key env vars:

- `REGISTRY` (default: `registry.benac.dev`)
- `REGISTRY_NAMESPACE` (default: `ourbox`)
- `REGISTRY_CA_CERT` (optional path; if your registry uses a private CA)
- `DOCKER` (override container CLI; can be `nerdctl` or `sudo nerdctl`, etc.)

## tools/mirror-required-images.sh

Purpose:

- one-time mirroring of upstream images into your registry so builds can run without DockerHub.

Run:

```bash
./tools/mirror-required-images.sh
```

## tools/pull-required-images.sh

Purpose:

* pulls required images from **your registry**
* tags them to the “canonical” names that `pi-gen` expects (example: `debian:trixie`)

Run:

```bash
./tools/pull-required-images.sh
```

Typically called by `build-image.sh`.

## tools/build-image.sh

Purpose:

* builds the OS image using upstream `pi-gen` container workflow
* binds this repo into the build container so custom stages are available
* ensures build prerequisites (buildkitd for nerdctl)
* ensures required base images are pulled/tagged appropriately

Run:

```bash
OURBOX_VARIANT=dev OURBOX_VERSION=dev ./tools/build-image.sh
```

Common issue: `pigen_work` leftover container.
See: `docs/runbooks/clean-build-environment.md`

## tools/publish-os-artifact.sh

Purpose:

* finds `deploy/img-*.img.xz`
* creates an OCI image containing `/artifact/os.img.xz`, `/artifact/os.info`, `/artifact/build.log`
* pushes it to `$REGISTRY/$REGISTRY_NAMESPACE/os:<tag>`

Run:

```bash
./tools/publish-os-artifact.sh deploy
```

## tools/pull-os-artifact.sh

Purpose:

* pulls the published artifact image
* creates a temporary container
* copies `/artifact/*` out to a local directory

Run:

```bash
./tools/pull-os-artifact.sh <registry-image-ref> ./deploy-from-registry
```

## pigen/ (OurBox customization)

* `pigen/config/ourbox.conf`
  pi-gen config entrypoint for OurBox builds.

* `pigen/stages/stage-ourbox-mini/`
  Adds OurBox Mini-specific behavior:

  * `/etc/ourbox/release`
  * `/etc/fstab` entry for `OURBOX_DATA` mount
  * SSD TRIM timer

* `pigen/overrides/`
  Overrides upstream pi-gen behavior (example: suppress exports we don’t want).

## vendor/pi-gen (submodule)

Upstream source of truth for image building. Treat as vendored dependency:

* prefer submodule pinning
* update intentionally
* document behavior changes (Debian base, kernel, partitions, etc.)
