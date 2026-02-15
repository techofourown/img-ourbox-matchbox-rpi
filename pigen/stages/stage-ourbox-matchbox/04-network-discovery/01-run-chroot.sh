#!/bin/bash -e

systemctl enable avahi-daemon.service
systemctl enable ourbox-mdns-aliases.service

# NOTE: Do NOT mask NetworkManager. It is the sole DHCP client on this
# Debian Trixie pi-gen image (dhcpcd is not installed, ifupdown is excluded).
# Avahi and NetworkManager coexist without conflict.
