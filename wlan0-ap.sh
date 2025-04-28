#!/usr/bin/env bash

set -euo pipefail

# Bring the interface down (in case it's managed) and back up. systemd-networkd is separately
# configured to assign the IPv4 and IPv6 subnets to wlan0.
ip link set dev wlan0 down 2>/dev/null || true
ip link set dev wlan0 up
