# Common issues

## 1) “Could not resolve hostname centroid”

Cause: DNS/hosts missing.

Fix:

- Use the IP (LAN) directly, or add a hosts entry:

```bash
echo "192.168.29.10 centroid" | sudo tee -a /etc/hosts
getent hosts centroid
```

## 2) SCP “No such file or directory”

Usually a copy/paste formatting issue, or wrong path.

Confirm path on the source machine:

```bash
ssh <user>@<host> 'ls -lh /path/to/os.img.xz'
```

Then scp exactly:

```bash
scp <user>@<host>:/path/to/os.img.xz /root/os.img.xz
```

## 3) Registry pull fails (TLS / unknown CA)

If you use a private registry CA:

* install the CA in the host trust store (platform-specific), or
* set/use the registry CA support in tooling if provided

Fallback: skip registry distribution and use SCP/USB transfer.

## 4) `pigen_work` exists

See: `docs/runbooks/clean-build-environment.md`

## 5) DATA disk didn’t mount at `/var/lib/ourbox`

Check label exists:

```bash
ls -l /dev/disk/by-label/OURBOX_DATA
```

Check fstab:

```bash
grep -n 'OURBOX_DATA' /etc/fstab
```

Check boot logs:

```bash
journalctl -b | grep -i ourbox
journalctl -b | grep -i 'var-lib-ourbox'
```

## 6) Still booting from SD card after flashing NVMe

* remove SD card
* ensure firmware boot order prefers NVMe
* verify root device:

```bash
findmnt /
```

## 7) “Wi-Fi is currently blocked by rfkill…”

Set regulatory domain:

```bash
sudo raspi-config
# Localisation Options -> WLAN Country
```
