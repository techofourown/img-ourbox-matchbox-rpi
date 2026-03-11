# Installer runtime fetch (Matchbox)

## Defaults
- Config shipped in image: `/opt/ourbox/installer/defaults.env`
- Optional override on boot media: `/boot/firmware/ourbox-installer.env`

`defaults.env` is rendered at installer image build time. It is not a static checked-in runtime file.

Key variables:
- `INSTALL_DEFAULTS_REF` (default `ghcr.io/techofourown/sw-ourbox-os/install-defaults:stable`)
- `INSTALLER_ID` (`matchbox`)
- `INSTALLER_VERSION` — installer artifact version baked at image build time
- `INSTALLER_GIT_HASH` — git SHA of this repo baked at image build time
- `OS_REPO` (default `ghcr.io/techofourown/ourbox-matchbox-os`)
- `OS_TARGET` (`rpi`)
- `OS_CHANNEL` (`stable`) – fallback channel if no explicit default ref is provided
- `OS_DEFAULT_REF` (optional digest/tag ref for "press ENTER" default)
- `CHANNEL_STABLE_TAG`, `CHANNEL_BETA_TAG`, `CHANNEL_NIGHTLY_TAG`, `CHANNEL_EXP_LABS_TAG`
- `OS_REF` (full ref, bypasses channel)
- `OS_CATALOG_ENABLED` (`1`) and `OS_CATALOG_TAG` (`${OS_TARGET}-catalog`)
- `OS_ORAS_VERSION` (`1.3.0`)
- `OS_REGISTRY_USERNAME` / `OS_REGISTRY_PASSWORD` (optional for private repos)

## Artifact contract (oras pull)
- Type: `application/vnd.techofourown.ourbox.matchbox.os-image.v1`
- Required files:
  - `os.img.xz`
  - `os.img.xz.sha256` (first field is the digest; required, install fails if missing/invalid)
  - `os.meta.env` (KEY=VALUE; include version/target/sku/k3s/git sha + platform contract digest)
- Optional: `os.meta.json`, `os.info`, `build.log`

## Runtime UX
- Shared selection policy is sourced from `/opt/ourbox/tools/installer-selection-resolver.sh`, the
  upstream reference resolver defined in `sw-ourbox-os`.
- The vendored resolver copy is checked in CI against the upstream revision recorded in
  `tools/installer-selection-resolver.upstream.env`.
- Shared installer SSH policy is sourced from `/opt/ourbox/tools/installer-ssh-helper.sh`, the
  upstream reference helper and contract defined in `sw-ourbox-os`.
- The vendored installer SSH helper copy is checked in CI against the upstream revision recorded in
  `tools/installer-ssh-helper.upstream.env`.
- Installer logs its operator-visible flow to `/run/ourbox-installer.log` in addition to `tty1`,
  so support media can inspect the same transcript over SSH.
- Installer loads baked defaults, then attempts to pull `${INSTALL_DEFAULTS_REF}` and apply `defaults/${INSTALLER_ID}.env`.
- If remote defaults pull fails, installer falls back to baked defaults.
- Boot-media override (`/boot/firmware/ourbox-installer.env`) is applied last and wins for runtime
  payload-selection controls. It does not override installer SSH policy.
- A non-empty baked `OS_DEFAULT_REF` remains in force unless remote install-defaults explicitly replaces it with another non-empty ref.
- Matchbox now follows a four-step installer flow:
  1) resolve the OS payload
  2) review the SYSTEM/DATA storage plan
  3) set first-boot identity
  4) review a final summary and type `INSTALL`
- Installer shows both NVMe disks in a numbered menu and requires an explicit SYSTEM-disk confirmation before continuing; the other NVMe becomes DATA for that install.
- If the chosen SYSTEM disk currently carries `LABEL=OURBOX_DATA`, installer warns that the label will be cleared as part of the later SYSTEM wipe.
- If the chosen DATA disk already contains OurBox state, installer offers `RESET-BOOTSTRAP`, `ERASE-DATA`, or `KEEP-DATA` during planning and applies the chosen action only after the final `INSTALL` confirmation.
- `KEEP-DATA` preserves existing DATA contents; bootstrap re-runs automatically on next boot only when the shipped contract state changed.
- Matchbox no longer requires the operator to type the raw SYSTEM disk path or `FLASH`; destructive work starts only after the final `INSTALL` confirmation step.
- Default action order:
  1) `OS_REF` (if set)
  2) `OS_DEFAULT_REF` (if set)
  3) newest valid digest-pinned catalog row for `OS_CHANNEL`
  4) `${OS_REPO}:<tag for OS_CHANNEL>` fallback (stable/beta/nightly/exp-labs mapping)
- Catalog resolution is row-order independent: it filters by channel, requires a digest-pinned
  `pinned_ref`, and picks the newest row by `created`.
- Floating refs are resolved to digests with `oras resolve` and pulled immutably by digest; the
  installer fails closed unless `OURBOX_ALLOW_UNRESOLVED_PULL=1` is set for development/testing.
- Interactive options on boot:
  - `c` choose channel (stable/beta/nightly/exp-labs/custom); named lanes prefer the newest
    digest-pinned catalog row and fall back to the lane tag only when catalog resolution is not
    available
  - `l` list digest-pinned entries from `${OS_TARGET}-catalog` if present (newest first by `created`)
  - `r` enter custom ref (tag or digest)
  - `o` override OS payload repo/tag defaults interactively
- Installer boot waits for `network-online.target` and bootstraps ORAS if missing.
- After flashing, the installer appends payload-selection provenance to the installed
  `/etc/ourbox/release` before poweroff.

## Installer SSH policy
- Shared installer SSH semantics come from the upstream `sw-ourbox-os` installer SSH contract and
  the vendored helper at `/opt/ourbox/tools/installer-ssh-helper.sh`.
- Matchbox keeps installer SSH policy at image-build time. Boot-media runtime overrides from
  `/boot/firmware/ourbox-installer.env` do not apply to `OURBOX_INSTALLER_SSH_*` knobs.
- Official/public Matchbox media currently ships with `OURBOX_INSTALLER_SSH_MODE=off`, meaning the
  shared contract exposes no usable installer SSH login path.
- SSH-enabled Matchbox support or lab media is explicit opt-in only. `key` mode requires explicit
  `OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS`, `password` mode requires explicit
  `OURBOX_INSTALLER_SSH_PASSWORD_HASH`, and `both` requires at least one usable auth input.
- Matchbox does not currently support local runtime password generation for installer SSH.
  `OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY` stays `0`.

## Official builds
- Official Matchbox workflows now publish the OS artifact first, then build the installer with that exact digest-pinned OS ref baked into `OS_DEFAULT_REF`.
- Official installers bake `INSTALL_DEFAULTS_REF=''` for deterministic default installs; operators can still override via `/boot/firmware/ourbox-installer.env`.
- Official/public installers also set the full installer SSH posture explicitly in workflow code and
  currently use `OURBOX_INSTALLER_SSH_MODE=off`.
- Push-to-`main` official candidate builds consume the generated pinned refs in `release/official-inputs.env` and publish the `beta` lane.
- Stable builds are a promotion of that already-published candidate digest once both candidate success and a matching published GitHub Release are present; they are not rebuilt on release.
- Scheduled nightly integration builds resolve the latest `sw-ourbox-os` `edge` platform bundle digests at workflow time and publish the `nightly` lane.
- GitHub prereleases authorize promotion of the same candidate digest into `exp-labs`, and either the candidate or the prerelease event may wake that promotion after the other condition already exists.
- Promotion is driven by `candidate-provenance.json`; it does not use artifact-carried `.env` sidecars as promotion control-plane inputs.

## Catalog TSV
- Tag: `${OS_TARGET}-catalog`
- Columns: `channel tag created version variant target sku git_sha platform_contract_digest k3s_version img_sha256 artifact_digest pinned_ref`
- Kept up to date automatically by `tools/publish-os-artifact.sh` when channel tags are pushed.
- `channel` stores the short release channel name (`stable`, `beta`, `nightly`, `exp-labs`).
- Resolver behavior does not depend on append order; `created` is the tie-breaker.
