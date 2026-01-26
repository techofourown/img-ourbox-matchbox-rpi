# Release process

This repo uses semantic-release to generate tags and changelog entries.

## What semantic-release does here

Configured in `.releaserc.cjs`:

- watches `main`
- creates tags `vX.Y.Z`
- updates `CHANGELOG.md`
- creates GitHub release notes

## What it does NOT do (currently)

Semantic-release does not automatically:

- build OS images
- publish OS artifacts to the registry

We treat the “real” OS deliverable as the registry artifact reference emitted by:

```bash
./tools/publish-os-artifact.sh deploy
```

## Recommended “release” workflow (human process)

1. Make changes (stages/tools/docs)
2. Build and boot-test at least once on real hardware
3. Publish OS artifact to registry
4. Record the artifact image ref in release notes or an internal tracker
5. Merge to `main` with Conventional Commits so semantic-release can cut a tag

## Commit conventions

Use Conventional Commits:

* `feat: ...` → minor bump
* `fix: ...` → patch bump
* `feat!: ...` → major bump

## If you need an internal “artifact catalog”

A simple approach:

* keep a short table in an internal doc/wiki noting:

  * git tag (`vX.Y.Z`)
  * registry artifact ref (`registry.../ourbox/os:...`)
  * hardware validation status (boot OK, mount OK)
