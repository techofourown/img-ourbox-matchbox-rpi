# Quickstart: Build → Publish → Pull → Flash → Boot

This is the “someone new can do it” path.

If you want deeper details for a step, each section links to the longer guide.

## Overview

- Build host: any machine with Docker/nerdctl/podman
- Target: Raspberry Pi device with **two NVMe** drives:
  - **SYSTEM** NVMe: gets flashed (destroyed)
  - **DATA** NVMe: labeled `OURBOX_DATA`, mounts at `/var/lib/ourbox`

## 1) Build the image

From the repo root on the build host:

```bash
git submodule update --init --recursive

# Optional one-time (if you want registry mirroring)
./tools/mirror-required-images.sh

# Build
OURBOX_VARIANT=dev OURBOX_VERSION=dev ./tools/build-image.sh
```

Details: `02-build-image.md`

## 2) Publish the OS artifact to the registry

```bash
./tools/publish-os-artifact.sh deploy
```

Details: `03-publish-and-pull-artifact.md`

## 3) Pull the artifact on the machine that will flash

```bash
./tools/pull-os-artifact.sh <registry-image-ref> ./deploy-from-registry
ls -lah ./deploy-from-registry
```

You should see:

* `os.img.xz`
* `os.info`
* `build.log`

## 4) Copy the image to the Raspberry Pi (if needed)

Option A: Pull on the Pi directly (if it has container tooling + registry access)

Option B: SCP the file:

```bash
scp ./deploy-from-registry/os.img.xz root@<pi-ip>:/root/os.img.xz
```

## 5) Flash the SYSTEM NVMe (destructive)

Follow the safety-first guide:

* `04-flash-system-nvme.md`

## 6) Boot and verify

After booting into NVMe:

* confirm `/` is NVMe
* confirm `/var/lib/ourbox` mounts from `LABEL=OURBOX_DATA`

Checklist:

* `05-first-boot-checklist.md`
