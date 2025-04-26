#!/usr/bin/env bash
# Ensure wormhole’s own traffic uses the local router's internet connection

set -euo pipefail

SRC4=$(ip -4 -o addr show dev eth0 scope global | awk '{print $4; exit}')
GW4=$(ip route show default | awk '/^default.*eth0/ {print $3; exit}')

if [[ -n "$SRC4" && -n "$GW4" ]]; then
  ip route del default table localwan 2>/dev/null || true
  ip route add default via "$GW4" dev eth0 table localwan

  ip rule del from "$SRC4" lookup localwan priority 100 2>/dev/null || true
  ip rule add from "$SRC4" lookup localwan priority 100
fi

SRC6=$(ip -6 -o addr show dev eth0 scope global | awk '{print $4; exit}')
GW6=$(ip -6 route show default | awk '/^default.*eth0/ {print $3; exit}')

if [[ -n "$SRC6" && -n "$GW6" ]]; then
  ip -6 route del default table localwan 2>/dev/null || true
  ip -6 route add default via "$GW6" dev eth0 table localwan

  ip -6 rule del from "$SRC6" lookup localwan priority 100 2>/dev/null || true
  ip -6 rule add from "$SRC6" lookup localwan priority 100
fi
