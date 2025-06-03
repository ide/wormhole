# Exit node setup

Installed Tailscale: https://tailscale.com/kb/1174/install-debian-bookworm
Enabled IP forwarding: https://tailscale.com/s/ip-forwarding
Advertised it as an exit node: https://tailscale.com/kb/1103/exit-nodes
Configured it to be an exit node and disabled key expiry through the Tailscale website

Disabled swap:
```
sudo systemctl disable dphys-swapfile.service
```

Disabled Bluetooth and Wi-Fi in /boot/firmware/config.txt:
```
dtoverlay=disable-bt
dtoverlay=disable-wifi
```

Enabled ufw:
```
sudo apt install ufw

sudo ufw --force reset

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed

sudo ufw allow ssh
sudo ufw route allow in on tailscale0 comment 'Tailnet to WAN'

sudo ufw enable
```
