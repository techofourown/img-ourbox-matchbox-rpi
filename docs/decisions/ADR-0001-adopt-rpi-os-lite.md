# ADR-0001: Adopt Raspberry Pi OS Lite as the Base Operating System for OurBox Mini

## Status
Accepted

## Context

OurBox Mini (TOO-OBX-MINI-01) is a physical appliance built around **Raspberry Pi 5 (16 GB RAM)**
with a **dual NVMe SSD HAT**, designed to remain plugged in continuously and run the OurBox software
stack (delivered primarily via containers, orchestrated by k3s). The product’s trust promise depends
not only on open-source code, but also on the long-term ability to keep devices secure, stable, and
supportable as a shipped hardware product.

We must choose a **single supported/validated base OS** (“OurBox OS” for this SKU) that minimizes
hardware enablement surprises (boot/firmware/NVMe/Wi‑Fi), reduces support burden, and provides a
stable baseline for years of updates. We also want an OS choice that aligns with TOOO’s principles of
user autonomy and avoids unnecessary ecosystem lock-in.

We considered three candidate distributions for this Raspberry Pi-based appliance:
**Ubuntu Server LTS (ARM64)**, **Raspberry Pi OS Lite (64-bit)**, and **Ubuntu Core**. The decision
is specific to **OurBox Mini’s Pi-based hardware**; other future OurBox SKUs may choose a different
baseline.

## Decision

For **OurBox Mini (TOO-OBX-MINI-01)**, we will adopt **Raspberry Pi OS Lite (64-bit)** as the
supported/validated base operating system (“OurBox OS” for this SKU).

OurBox’s application stack will remain **container-first** (k3s + workloads), so the base OS is
primarily responsible for **hardware enablement, secure boot/runtime fundamentals, networking, and
storage stability**. We will treat Ubuntu Server LTS (ARM64) and Ubuntu Core as alternatives to
re-evaluate for future SKUs and/or future revisions if requirements change.

## Rationale

Raspberry Pi OS Lite (64-bit) is selected because it provides the lowest-risk foundation for a
Pi-based appliance:

- **Best-fit hardware enablement for Raspberry Pi 5 + accessories.** Raspberry Pi OS is the most
  aligned with the Raspberry Pi platform’s firmware/kernel expectations and the surrounding
  ecosystem (NVMe HATs, boot behavior, device-specific quirks). This reduces “hardware tax” and
  unpredictable breakage that becomes expensive in customer support.
- **Lowest support burden and strongest ecosystem defaults.** When customers and contributors use
  Raspberry Pi hardware, Raspberry Pi OS is the common reference point. Documentation,
  troubleshooting patterns, and community knowledge are most consistent in this environment, which
  improves maintainability and onboarding.
- **Minimal base, no specialized packaging constraints.** Lite is small enough to keep surface area
  down and supports standard Debian-style packaging, without forcing an “appliance-only” packaging
  model that could constrain how we deliver and debug our stack.
- **Aligns with TOOO autonomy goals.** Raspberry Pi OS is a straightforward, widely understood Linux
  base. Users can rebuild, inspect, and maintain the device without being tied to a specialized OS
  ecosystem. This supports our long-term “exit-to-self-sufficiency” posture.

Ubuntu Server LTS (ARM64) remains attractive for cross-hardware standardization, and Ubuntu Core is
attractive for transactional updates, but for a Pi-based v1 appliance we prioritize **hardware
predictability and supportability** over uniformity or specialized update models.

## Consequences

### Positive
- **Reduced risk of hardware-related failures** (boot, firmware/kernel, NVMe HAT behavior,
  networking) on Raspberry Pi 5.
- **Lower customer support burden** due to alignment with the dominant Raspberry Pi ecosystem
  defaults and documentation.
- **Faster time-to-ship** for the appliance SKU by minimizing integration friction and “unknown
  unknowns.”
- **Clear baseline for validation**: a single OS target simplifies QA, test images, and a stable
  “known good” platform.

### Negative
- **Non-transactional OS updates** by default (traditional package updates), increasing the need for
  careful update practices and recovery planning.
- **Less uniformity across future non-Pi SKUs**, since Raspberry Pi OS is Pi-centric and not
  necessarily the best baseline for x86 or other ARM boards.
- **Potentially older package versions** compared to some alternatives; we must be intentional about
  what lives in the base OS versus containers.

## Mitigation
- **Keep the base OS minimal and treat it as “firmware + host.”** Run OurBox features primarily in
  containers so most updates and rollbacks happen at the application layer.
- **Harden the host OS** (disable unnecessary services, conservative defaults, least-open network
  posture) and adopt a disciplined patching process.
- **Build and maintain a reproducible image pipeline** for OurBox Mini (standardized provisioning +
  configuration), so field devices converge on a known-good state.
- **Implement a recovery story** (documented restore path; optional backup/restore tooling) so
  OS-level issues are survivable.
- **Re-evaluate OS choices per SKU** as the hardware portfolio expands (e.g., Ubuntu Server LTS for
  cross-platform uniformity, or an immutable/transactional base for higher-end appliances), while
  keeping the application stack portable.
