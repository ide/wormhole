#!/usr/bin/env bash
# Usage:   sudo ./setup.sh [EXIT_NODE_HOSTNAME] [SSID] [PASSPHRASE]
# Example: sudo ./setup.sh exitportal wormhole ChangeMe123
# 
# Environment variables (used as fallback):
#   WORMHOLE_EXIT_NODE       - Tailscale hostname of the exit node
#   WORMHOLE_WIFI_SSID       - Wi-Fi access point SSID
#   WORMHOLE_WIFI_PASSPHRASE - WPA2 key (≥8 chars)

set -euo pipefail

# Get variables with fallback: CLI args -> env vars -> defaults/empty
EXIT_NODE=${1:-${WORMHOLE_EXIT_NODE:-}}
SSID=${2:-${WORMHOLE_WIFI_SSID:-wormhole}}
PASSPHRASE=${3:-${WORMHOLE_WIFI_PASSPHRASE:-}}

# Error if required variables are missing
if [ -z "$EXIT_NODE" ]; then
    echo "Error: Exit node not specified. Provide as first argument or set WORMHOLE_EXIT_NODE environment variable."
    echo "Usage: sudo $0 [EXIT_NODE_HOSTNAME] [SSID] [PASSPHRASE]"
    exit 1
fi

if [ -z "$PASSPHRASE" ]; then
    echo "Error: Wi-Fi passphrase not specified. Provide as third argument or set WORMHOLE_WIFI_PASSPHRASE environment variable."
    echo "Usage: sudo $0 [EXIT_NODE_HOSTNAME] [SSID] [PASSPHRASE]"
    exit 1
fi

# Require sudo
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo privileges."
  echo "Usage: sudo $0 [EXIT_NODE_HOSTNAME] [SSID] [PASSPHRASE]"
  exit 1
fi

# Add Tailscale repository
if ! dpkg -s apt-transport-https >/dev/null 2>&1; then
  apt update
  apt install -y apt-transport-https
fi
if ! apt-key list | grep Tailscale >/dev/null; then
  curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.gpg | apt-key add -
fi
if [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
  curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.list > /etc/apt/sources.list.d/tailscale.list
fi

# Install packages
if ! dpkg -s hostapd dnsmasq tailscale >/dev/null 2>&1; then
  apt update
  apt install -y hostapd dnsmasq tailscale
fi

# Copy configuration files
mkdir -p /etc/systemd/system/hostapd.service.d

install -m644 99-wormhole.conf          /etc/sysctl.d/99-wormhole.conf
install -m644 20-wlan0.network          /etc/systemd/network/20-wlan0.network
install -m644 dnsmasq.conf              /etc/dnsmasq.d/wormhole.conf
install -m755 route-ap-clients.sh       /usr/local/sbin/route-ap-clients.sh
install -m644 route-ap-clients.service  /etc/systemd/system/route-ap-clients.service
install -m644 hostapd.conf              /etc/hostapd/hostapd.conf
install -m755 wlan0-ap.sh               /usr/local/sbin/wlan0-ap.sh
install -m644 10-wlan0-ap.conf          /etc/systemd/system/hostapd.service.d/10-wlan0-ap.conf

# Patch SSID and passphrase
sed -i "s/^ssid=.*/ssid=${SSID}/" /etc/hostapd/hostapd.conf
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${PASSPHRASE}/" /etc/hostapd/hostapd.conf

# Load hostapd configuration file
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Enable forwarding immediately
sysctl --system

# Routing table entries for the remote router's internet connection
if ! grep -q '^100	exitnode4' /etc/iproute2/rt_tables; then
  echo '100	exitnode4' >> /etc/iproute2/rt_tables
fi
if ! grep -q '^101	exitnode6' /etc/iproute2/rt_tables; then
  echo '101	exitnode6' >> /etc/iproute2/rt_tables
fi

# Free wlan0 from wpa_supplicant
systemctl mask --now wpa_supplicant.service

# Use systemd-networkd to manage wlan0
systemctl daemon-reload
systemctl enable --now systemd-networkd
systemctl reload systemd-networkd

# hostapd may be masked if Raspberry Pi OS was not initialized with an SSID and passphrase
systemctl unmask hostapd
systemctl enable --now hostapd dnsmasq route-ap-clients
systemctl reload dnsmasq

# Route traffic through the exit node
tailscale login
tailscale up --exit-node="${EXIT_NODE}" --exit-node-allow-lan-access

echo 'Setup complete. Reboot recommended. Confirm AP mode with: iw dev wlan0 info'
