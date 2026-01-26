# Publish and pull the OS artifact via OCI registry

This repo uses a practical trick:

> Wrap `os.img.xz` (and metadata) into a `FROM scratch` OCI image and push it to a registry.

Why:

- registries are great at distributing large blobs
- every host already knows how to `pull`
- we get a stable “image reference” instead of random file transfer workflows

## Publish (build host)

After a successful build, publish from the deploy directory:

```bash
./tools/publish-os-artifact.sh deploy
```

The script will:

* locate `deploy/img-*.img.xz`
* build an OCI image containing:

  * `/artifact/os.img.xz`
  * `/artifact/os.info`
  * `/artifact/build.log`
* push it to:

  * `$REGISTRY/$REGISTRY_NAMESPACE/os:<tag>`

The script prints the final image reference. Save it somewhere.

## Pull and extract (any host)

```bash
./tools/pull-os-artifact.sh <registry-image-ref> ./deploy-from-registry
ls -lah ./deploy-from-registry
```

You should see:

* `os.img.xz`
* `os.info`
* `build.log`

## Validating the image file

Before flashing:

```bash
xz -t ./deploy-from-registry/os.img.xz
sha256sum ./deploy-from-registry/os.img.xz | tee ./deploy-from-registry/os.img.xz.sha256
```

## Next step

* Flash guide: `04-flash-system-nvme.md`
