#!/usr/bin/env bash

set -euo pipefail

# This script ensures all client traffic arriving on wlan0 (the AP interface) is routed through the
# remote Tailscale exit node, while all other traffic from this device uses the default (local WAN)
# route. IPv4 and IPv6 are both handled.

# -------------------------
# IPv4 policy routing setup
# -------------------------

# Add a default route to the "exitnode4" pointing to the tailscale0 interface
ip route del default table exitnode4 2>/dev/null || true
ip route add default dev tailscale0 table exitnode4

# Make packets marked with fwmark=1 use the "exitnode4" table
ip rule del fwmark 1 table exitnode4 priority 100 2>/dev/null || true
ip rule add fwmark 1 table exitnode4 priority 100

# Mark all IPv4 packets entering on wlan0 with fwmark=1
iptables -t mangle -C PREROUTING -i wlan0 -j MARK --set-mark 1 \
  || iptables -t mangle -A PREROUTING -i wlan0 -j MARK --set-mark 1

# -------------------------
# IPv6 policy routing setup
# -------------------------

ip -6 route del default table exitnode6 2>/dev/null || true
ip -6 route add default dev tailscale0 table exitnode6

ip -6 rule del fwmark 1 table exitnode6 priority 100 2>/dev/null || true
ip -6 rule add fwmark 1 table exitnode6 priority 100

ip6tables -t mangle -C PREROUTING -i wlan0 -j MARK --set-mark 1 \
  || ip6tables -t mangle -A PREROUTING -i wlan0 -j MARK --set-mark 1
