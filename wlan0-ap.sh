#!/usr/bin/env bash
# Brings up wlan0 and assign AP IPs

set -euo pipefail

# Bring interface down (in case it's managed) and back up
ip link set dev wlan0 down 2>/dev/null || true
ip link set dev wlan0 up

# Remove any old addresses, then assign exactly what hostapd expects
ip addr flush dev wlan0
ip addr add 192.168.8.1/24 dev wlan0
ip -6 addr add fd7e:8:8::1/64 dev wlan0
