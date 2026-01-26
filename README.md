# img-ourbox-mini-rpi

Image build repository for **OurBox Mini** targeting Raspberry Pi hardware. Use this repo for image
recipes, build tooling, and release artifacts aligned with the OurBox OS and OurBox Mini hardware
specs.

See `docs/` for RFC/ADR scaffolding.

## Quickstart (Centroid registry-first)

### 1) Seed the registry (one-time, from a machine that can reach DockerHub)
```bash
./tools/mirror-required-images.sh

