#!/usr/bin/env bash
# Usage:   sudo ./setup.sh <EXIT_NODE_HOSTNAME> <SSID> <PASSPHRASE>
# Example: sudo ./setup.sh exitportal wormhole ChangeMe123

set -euo pipefail

EXIT_NODE=${1:-exit} # Tailscale hostname of the exit node
SSID=${2:-wormhole}  # Wi-Fi access point SSID
PASSPHRASE=${3}      # WPA2 key (≥8 chars)

# Require sudo
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo privileges."
  echo "Usage: sudo $0 <EXIT_NODE_HOSTNAME> <SSID> <PASSPHRASE>"
  exit 1
fi

# # Add Tailscale repository
# apt install -y apt-transport-https
# curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.gpg | apt-key add -
# curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.list | tee /etc/apt/sources.list.d/tailscale.list

# # Install packages
# apt update
# apt install -y hostapd dnsmasq tailscale

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

# systemd enablement
systemctl daemon-reload
systemctl reload systemd-networkd
systemctl enable --now hostapd dnsmasq route-ap-clients

# Route traffic through the exit node
tailscale up --exit-node="${EXIT_NODE}" --exit-node-allow-lan-access

echo 'Setup complete. Reboot recommended. Confirm AP mode with: iw dev wlan0 info'
