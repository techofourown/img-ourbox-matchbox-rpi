# Build the OS image

This guide covers building the OurBox Mini OS image using `pi-gen` inside a container.

## Prerequisites

On the build host you need one of:

- `nerdctl` (containerd)
- `docker`
- `podman`

And standard utilities:

- `bash`
- `git` + submodules
- enough disk space for pi-gen output (several GB)

## One-time setup: submodule

```bash
git submodule update --init --recursive
```

## Optional: configure registry defaults

The tooling reads optional config from:

* `tools/registry.env` (committed defaults)
* OR environment variables at runtime

Key variables:

* `REGISTRY` (default: `registry.benac.dev`)
* `REGISTRY_NAMESPACE` (default: `ourbox`)
* `REGISTRY_CA_CERT` (optional; if you use a private CA)

## Optional: mirror upstream base images into your registry

If you want builds to work without DockerHub access:

```bash
./tools/mirror-required-images.sh
```

This mirrors base dependencies (e.g. `debian:trixie`, buildkit image) into your registry.

## Build

Typical dev build:

```bash
OURBOX_VARIANT=dev OURBOX_VERSION=dev ./tools/build-image.sh
```

Optional variables:

* `OURBOX_TARGET` (default: `rpi`)
* `OURBOX_SKU` (default: `TOO-OBX-MINI-01`)
* `OURBOX_VARIANT` (e.g. `dev`, `prod`)
* `OURBOX_VERSION` (e.g. `dev`, `0.1.0`)

### Common pitfall: `pigen_work already exists`

If the build was interrupted, you may see:

> Container pigen_work already exists and you did not specify CONTINUE=1.

Fix options:

1. Clean rebuild:

```bash
nerdctl rm -v pigen_work || true
# or: docker rm -v pigen_work || true
```

2. Continue:

```bash
CONTINUE=1 ./tools/build-image.sh
```

See runbook: `docs/runbooks/clean-build-environment.md`

## Build output

Successful builds produce a `deploy/` directory containing:

* `img-*.img.xz` (compressed disk image)
* `*.info` (build info)
* `build.log`

These are build outputs and should not be committed.

## Next step

* Publish artifact: `03-publish-and-pull-artifact.md`
