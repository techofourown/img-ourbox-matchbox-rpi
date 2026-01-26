# ADR-0003: Distribute OS images as OCI artifacts via a container registry

## Status
Accepted

## Context

OS image builds produce large artifacts (`*.img.xz`) that must be transferred to other machines for:

- flashing devices
- reproducing or recovering builds
- sharing a known-good image with another operator

Ad-hoc file transfer (SCP/USB) works but is inconsistent and hard to standardize.

We already operate a container registry and have standard tooling to pull blobs efficiently.

## Decision

We will distribute OS images by:

- wrapping `os.img.xz` (and metadata) into a `FROM scratch` OCI image containing `/artifact/*`
- pushing to `$REGISTRY/$REGISTRY_NAMESPACE/os:<tag>`
- retrieving via container CLI and extracting `/artifact/*`

This is implemented by:

- `tools/publish-os-artifact.sh`
- `tools/pull-os-artifact.sh`

## Rationale

- Registries solve “large artifact distribution” well (storage + content addressing + caching).
- Every operator already has a container CLI.
- The artifact reference becomes a stable identifier.

## Consequences

### Positive
- Standard transport path for OS artifacts
- Easier repeatability (“pull this ref and flash it”)

### Negative
- Requires registry access + trust (TLS/CA)
- OCI artifact is not a “standard” OS-image packaging format for all tooling

### Mitigation
- Keep SCP/USB as a documented fallback
- Keep metadata alongside the image (`os.info`, `build.log`)
