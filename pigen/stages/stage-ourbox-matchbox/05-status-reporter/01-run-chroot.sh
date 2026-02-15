#!/bin/bash -e

systemctl enable ourbox-status.service

# Clear the static MOTD so only our dynamic script runs
: > /etc/motd
