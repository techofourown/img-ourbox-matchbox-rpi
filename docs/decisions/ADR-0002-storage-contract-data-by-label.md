# ADR-0002: Adopt a label-based data mount contract for OurBox Mini

## Status
Accepted

## Context

OurBox Mini hardware includes two NVMe devices:

- a **SYSTEM** disk that is flashed with the OS image
- a **DATA** disk intended for persistent application storage

Device enumeration order (`nvme0n1` vs `nvme1n1`) is not guaranteed across boots, firmware versions,
or hardware differences. If we mount storage by kernel path, we risk mounting the wrong device.

We need a deterministic, low-risk contract that:

- survives enumeration changes
- supports safe automation
- avoids bricking the device when the data disk is missing or slow to appear

## Decision

We will standardize on:

- DATA filesystem: **ext4**
- DATA identity: filesystem **LABEL = `OURBOX_DATA`**
- Mount point: `/var/lib/ourbox`
- fstab entry uses label + resilient options:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

## Rationale

* Label-based mounts are stable and human-auditable.
* Label approach works well for field recovery (“relabel disk, reboot”).
* `nofail` ensures we can boot even if the data disk is absent.
* Short timeout prevents slow-boot failures due to NVMe timing.

## Consequences

### Positive

* Strong protection against wrong-disk mounts
* Simpler recovery story
* Works without additional discovery logic

### Negative

* Requires the DATA disk to be formatted and labeled correctly
* ext4 is Linux-native (not Windows-friendly)

### Mitigation

* Document the labeling/format steps (guide + troubleshooting)
* Keep the contract small and explicit; avoid hidden magic
