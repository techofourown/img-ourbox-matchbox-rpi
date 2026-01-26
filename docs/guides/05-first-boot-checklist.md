# First boot checklist

After booting the NVMe-flashed system, confirm the host contracts and basic readiness.

## 1) Confirm root is NVMe

```bash
findmnt /
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
```

## 2) Confirm release contract file exists

```bash
sudo cat /etc/ourbox/release
```

You should see `OURBOX_*` keys (SKU/variant/version/etc).

## 3) Confirm DATA mount contract

```bash
findmnt /var/lib/ourbox
df -hT /var/lib/ourbox
```

If the DATA disk is present and labeled correctly, `/var/lib/ourbox` should be mounted.

If it’s missing, the system should still boot (by design).

## 4) Confirm SSD hygiene timer

```bash
systemctl status fstrim.timer --no-pager
```

Should be enabled/active.

## 5) Networking + SSH

* Ensure you can SSH in from your admin host
* Consider adding a stable hostname/IP reservation in your router/DHCP

## 6) Wi‑Fi regulatory domain (if you need Wi‑Fi)

If you see:

> Wi-Fi is currently blocked by rfkill. Use raspi-config to set the country before use.

Fix:

```bash
sudo raspi-config
# Localisation Options -> WLAN Country
```

## 7) Snapshot state (recommended)

Capture:

```bash
uname -a
cat /etc/os-release
lsblk -f
cat /etc/fstab
```
