#!/bin/bash -e

systemctl enable avahi-daemon.service
systemctl enable ourbox-mdns-aliases.service

# Prevent NetworkManager from conflicting with dhcpcd (the default DHCP client).
# avahi-daemon can pull in NM-adjacent packages on Debian Trixie.
systemctl mask NetworkManager.service 2>/dev/null || true
