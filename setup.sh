#!/usr/bin/env bash
# Usage:   sudo ./setup.sh [EXIT_NODE_HOSTNAME] [SSID] [PASSPHRASE]
# Example: sudo ./setup.sh exitportal wormhole ChangeMe123
# 
# Environment variables (used as fallback):
#   WORMHOLE_EXIT_NODE       - Tailscale hostname of the exit node
#   WORMHOLE_WIFI_SSID       - Wi-Fi access point SSID
#   WORMHOLE_WIFI_PASSPHRASE - WPA2 key (≥8 chars)
#
# You can also create a .env file in the same directory with these variables

# Load .env file if it exists
if [ -f "$(dirname "$0")/.env" ]; then
    echo "Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source "$(dirname "$0")/.env"
    set +a  # disable automatic export
fi

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
if ! dpkg -s hostapd dnsmasq iptables-persistent tailscale >/dev/null 2>&1; then
  apt update
  apt install -y hostapd dnsmasq iptables-persistent tailscale
fi

# Copy configuration files
mkdir -p /etc/systemd/system/hostapd.service.d

install -m644 99-wormhole.conf          /etc/sysctl.d/99-wormhole.conf
install -m644 20-end0.network           /etc/systemd/network/20-end0.network
install -m644 20-wlan0.network          /etc/systemd/network/20-wlan0.network
install -m644 dnsmasq.conf              /etc/dnsmasq.d/wormhole.conf
install -m644 hostapd.conf              /etc/hostapd/hostapd.conf
install -m755 wlan0-ap.sh               /usr/local/sbin/wlan0-ap.sh
install -m644 10-wlan0-ap.conf          /etc/systemd/system/hostapd.service.d/10-wlan0-ap.conf

# Configure NetworkManager to ignore wlan0 (access point interface)
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
  if ! grep -q 'unmanaged-devices.*wlan0' /etc/NetworkManager/NetworkManager.conf; then
    # Check if [keyfile] section exists
    if grep -q "^\[keyfile\]" /etc/NetworkManager/NetworkManager.conf; then
      # Add unmanaged-devices to existing [keyfile] section
      sed -i '/^\[keyfile\]/a unmanaged-devices=interface-name:wlan0' /etc/NetworkManager/NetworkManager.conf
    else
      # Add [keyfile] section with unmanaged-devices
      echo -e "\n[keyfile]\nunmanaged-devices=interface-name:wlan0" >> /etc/NetworkManager/NetworkManager.conf
    fi
  fi
fi

# Patch SSID and passphrase
sed -i "s/^ssid=.*/ssid=${SSID}/" /etc/hostapd/hostapd.conf
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${PASSPHRASE}/" /etc/hostapd/hostapd.conf

# Load hostapd configuration file
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Enable forwarding immediately
sysctl --system

# Free wlan0 from wpa_supplicant
systemctl mask --now wpa_supplicant.service

# Use systemd-networkd to manage wlan0
systemctl daemon-reload
systemctl enable --now systemd-networkd
systemctl reload systemd-networkd

# hostapd may be masked if Raspberry Pi OS was not initialized with an SSID and passphrase
systemctl unmask hostapd
systemctl enable --now hostapd dnsmasq
systemctl reload dnsmasq

# Route traffic through the exit node
tailscale up --exit-node="${EXIT_NODE}" --exit-node-allow-lan-access

# Add NAT/masquerading
iptables -t nat -C POSTROUTING -s 192.168.8.0/24 -o tailscale0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 192.168.8.0/24 -o tailscale0 -j MASQUERADE

ip6tables -t nat -C POSTROUTING -s fd7e:8:8::/64 -o tailscale0 -j MASQUERADE 2>/dev/null || \
ip6tables -t nat -A POSTROUTING -s fd7e:8:8::/64 -o tailscale0 -j MASQUERADE

# Add forwarding rules between wlan0 and tailscale0
iptables -C FORWARD -i wlan0 -o tailscale0 -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i wlan0 -o tailscale0 -j ACCEPT

iptables -C FORWARD -i tailscale0 -o wlan0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i tailscale0 -o wlan0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

ip6tables -C FORWARD -i wlan0 -o tailscale0 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wlan0 -o tailscale0 -j ACCEPT

ip6tables -C FORWARD -i tailscale0 -o wlan0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i tailscale0 -o wlan0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo 'Setup complete. Reboot recommended. Confirm AP mode with: iw dev wlan0 info'
