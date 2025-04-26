#!/usr/bin/env bash
# Usage:   sudo ./setup.sh <EXIT_NODE_HOSTNAME> <SSID> <PASSPHRASE>
# Example: sudo ./setup.sh exitportal wormhole ChangeMe123

set -euo pipefail

EXIT_NODE=${1:-exit} # Tailscale hostname of the exit node
SSID=${2:-wormhole}  # Wi-Fi name
PASSPHRASE=${3}      # WPA2 key (≥8 chars)

# Require sudo
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo privileges."
  echo "Usage: sudo $0 <EXIT_NODE_HOSTNAME> <SSID> <PASSPHRASE>"
  exit 1
fi

# Add Tailscale repository
apt install -y apt-transport-https
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.gpg | apt-key add -
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bookworm.list | tee /etc/apt/sources.list.d/tailscale.list

# Install packages
apt update
apt install -y hostapd dnsmasq iptables-persistent tailscale

# Copy configuration files
install -m644 hostapd.conf      /etc/hostapd/hostapd.conf
install -m644 dnsmasq.conf      /etc/dnsmasq.d/wormhole.conf
install -m644 20-wlan0.network  /etc/systemd/network/20-wlan0.network
install -m644 30-eth0.network   /etc/systemd/network/30-eth0.network
install -m644 99-wormhole.conf  /etc/sysctl.d/99-wormhole.conf
install -m755 localwan.sh       /usr/local/sbin/localwan.sh
install -m644 wormhole-localwan.service /etc/systemd/system/wormhole-localwan.service

# Patch SSID and passphrase
sed -i "s/^ssid=.*/ssid=${SSID}/"           /etc/hostapd/hostapd.conf
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${PASSPHRASE}/" /etc/hostapd/hostapd.conf

# Load hostapd configuration file
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Enable forwarding immediately
sysctl --system

# Firewall rules (v4 + v6)
iptables -t nat -A POSTROUTING -s 192.168.8.0/24  -o tailscale0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o tailscale0 -j ACCEPT
iptables -A FORWARD -i tailscale0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

ip6tables -t nat -A POSTROUTING -s fd7e:8:8::/64 -o tailscale0 -j MASQUERADE
ip6tables -A FORWARD -i wlan0 -o tailscale0 -j ACCEPT
ip6tables -A FORWARD -i tailscale0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

netfilter-persistent save

# Routing table entry for the local router's internet connection
if ! grep -q '^200 localwan' /etc/iproute2/rt_tables; then
  echo '200 localwan' >> /etc/iproute2/rt_tables
fi

# Free wlan0 from wpa_supplicant
systemctl mask --now wpa_supplicant.service

# systemd enablement
systemctl enable --now hostapd dnsmasq systemd-networkd
systemctl daemon-reload
systemctl enable --now wormhole-localwan.service

# Route traffic through the exit node
tailscale up --exit-node="${EXIT_NODE}" --exit-node-allow-lan-access

# Note: confirm with iw dev wlan0 info
echo 'Setup complete. Reboot recommended.'
