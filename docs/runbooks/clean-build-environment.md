# Clean build environment (pi-gen container leftovers)

## Symptom

Build fails with:

> Container pigen_work already exists and you did not specify CONTINUE=1.

## Why it happens

Upstream pi-gen uses a persistent work container (`pigen_work`). If a build is interrupted or you
switch configs, pi-gen refuses to reuse it unless told.

## Fix: delete work container (clean rebuild)

With nerdctl:

```bash
nerdctl rm -v pigen_work || true
```

With docker:

```bash
docker rm -v pigen_work || true
```

Then rerun:

```bash
./tools/build-image.sh
```

## Alternative: continue

If you believe the previous build can be resumed:

```bash
CONTINUE=1 ./tools/build-image.sh
```

## Also consider cleaning deploy outputs

If your `deploy/` directory got weird perms or partial files:

```bash
sudo rm -rf deploy deploy-from-registry
```

(These are outputs; they should not be committed.)
