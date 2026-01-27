# img-ourbox-mini-rpi

Build repository for **OurBox Mini** OS images targeting **Raspberry Pi hardware** (Pi 5 + dual NVMe).

This repo produces an NVMe-bootable OS that mounts `/var/lib/ourbox` and boots into an airgapped
single-node k3s runtime via `ourbox-bootstrap`.

## Docs

- Operator runbook: [`docs/OPS.md`](./docs/OPS.md)
- Contracts reference: [`docs/reference/contracts.md`](./docs/reference/contracts.md)

## Happy path (build → publish → flash → boot)

```bash
git clone --recurse-submodules https://github.com/techofourown/img-ourbox-mini-rpi.git
cd img-ourbox-mini-rpi
./tools/ops-e2e.sh
```
