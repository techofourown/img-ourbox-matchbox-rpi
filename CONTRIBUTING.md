# Contributing

This repo builds the OurBox Mini OS image. The bar is “someone else can reproduce what you did and
flash it without guessing”.

## Principles

1) **Safety first**  
   Storage work must be explicit about SYSTEM vs DATA disks. Prefer `/dev/disk/by-id` and
   `/dev/disk/by-label` in docs and scripts.

2) **Reproducibility over cleverness**  
   Prefer pinned versions, deterministic tags, and scripts that run on fresh hosts.

3) **Keep the repo clean**  
   Do not commit OS images or build outputs.

## What not to commit

These are ignored by `.gitignore` and should remain that way:

- `deploy/`
- `deploy-from-registry/`
- `*.img`, `*.img.xz`, `*.info`, `build.log`, checksums, etc.

Artifacts should be:
- Published to the registry (preferred), or
- Copied via SCP/USB for ad-hoc work

## Development workflow

- Branch off `main`
- Use PRs if possible (even internally) so changes are reviewable
- Keep changes small and scoped:
  - “docs improvements”
  - “tooling bugfix”
  - “new stage for X”

## Commit message conventions

This repo uses semantic-release. Prefer Conventional Commits:

- `feat: ...` → minor bump
- `fix: ...` → patch bump
- `chore: ...` / `docs: ...` → patch bump (depending on config)
- `feat!: ...` or `BREAKING CHANGE:` → major bump

## Quality checks (recommended)

If you edit `tools/*.sh`:

- Run `shellcheck` locally (or in CI)
- Make scripts `set -euo pipefail`
- Prefer `#!/usr/bin/env bash`

## Submodule updates (`vendor/pi-gen`)

If you update the pi-gen submodule:

```bash
cd vendor/pi-gen
git fetch origin
git checkout <new-commit-or-tag>
cd ../..
git add vendor/pi-gen
git commit -m "chore(pi-gen): bump submodule to <sha>"
```

Also update docs if behavior changes (base Debian version, stages, etc.).

## Documentation updates

If you change workflow/tooling/contracts:

* Update **only** `docs/OPS.md` and/or `docs/reference/contracts.md`
* Do not add new guides/runbooks/troubleshooting pages unless there is a strong reason
