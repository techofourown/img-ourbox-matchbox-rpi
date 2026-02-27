# Platform Contract Consumption (Matchbox)

Matchbox is **only a consumer** of platform software. All manifests, static assets, and platform
images come from `sw-ourbox-os` via pinned OCI artifacts; nothing is authored or fetched ad-hoc in
this repo.

---

## Sources of truth

- `sw-ourbox-os` ADR-0009 (platform contract as OCI artifact)
- `sw-ourbox-os` artifact docs: https://github.com/techofourown/sw-ourbox-os/blob/main/docs/architecture/artifact-distribution-and-integration.md
- Pinned refs in this repo:
  - `contracts/platform-contract.ref` (arch-agnostic contract)
  - `contracts/airgap-platform.ref` (arch-specific bundle with k3s + images)

---

## Current state (OCI by digest)

Matchbox pulls two GHCR artifacts published by `sw-ourbox-os`:

1) **platform-contract** (arch-agnostic)
   - Contents: manifests, landing, todo-bloom assets, contract metadata
   - Pulled via `./tools/fetch-platform-contract.sh`
   - Synced into pi-gen via `./tools/sync-platform-contract-into-pigen.sh`

2) **airgap-platform** (arch-specific: arm64/amd64)
   - Contents: `k3s` binary, `k3s-airgap-images-<arch>.tar`, platform image tars, `manifest.env`
   - Pulled via `./tools/fetch-airgap-platform.sh` (which also triggers the contract sync)
   - Injected by pi-gen stage `02-airgap-platform`

Runtime expectation (in the built image):
- `/opt/ourbox/airgap/k3s/{k3s,k3s-airgap-images-*.tar}`
- `/opt/ourbox/airgap/platform/images/*.tar`
- `/opt/ourbox/airgap/platform/manifests/**`
- `/opt/ourbox/airgap/platform/{landing,todo-bloom}/**`
- `/opt/ourbox/airgap/platform/contract.env` + `contract.digest`

---

## Provenance recording

During build, `ourbox-release` generation records platform contract provenance in
`/etc/ourbox/release`:
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`

---

## Updating pins

1. Publish new `platform-contract` and `airgap-platform` (per arch) from `sw-ourbox-os`.
2. Update `contracts/platform-contract.ref` and `contracts/airgap-platform.ref` to the new digests.
3. Run `./tools/fetch-airgap-platform.sh` to pull/sync into `pigen/`.
4. Rebuild images; update release notes/changelog with the new digests.

---

## Relationship to OS image distribution

OCI distribution of the OS image (`os.img.xz`) is transport only (see ADR-0003). Platform contract
identity is separate and governed by `sw-ourbox-os`.

---

## Related docs

- `docs/decisions/ADR-0004-consume-platform-contract-from-sw-ourbox-os.md`
- `docs/reference/contracts.md`
- `docs/OPS.md`
