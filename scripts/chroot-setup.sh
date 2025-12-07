#!/bin/bash
set -e

echo "[CHROOT] Fixing apt sources (Debian 12 stable)..."
cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
EOF

echo "[CHROOT] Updating package index..."
apt update || exit 1


echo "[CHROOT] Installing LXDE desktop + input stack + WiFi + browser..."

apt install -y --no-install-recommends \
    # LXDE Desktop Environment
    lxde-core \
    lxsession \
    lxterminal \
    lxinput \
    # Xorg + input
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    xinit \
    udev \
    # Display manager
    lightdm \
    lightdm-gtk-greeter \
    dbus-x11 \
    # Browser
    chromium \
    # WiFi
    wpasupplicant \
    wireless-tools \
    network-manager \
    # Fonts
    fonts-dejavu \
    fonts-liberation \
    # Browser deps
    libgtk-3-0 \
    libnss3 \
    libasound2 \
    libgdk-pixbuf-2.0-0 \
    libatk1.0-0 \
    # Graphics utilities
    mesa-utils

echo "[CHROOT] Packages installed."


echo "[CHROOT] Enabling services (LightDM + NetworkManager + udev)..."
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable systemd-udevd
systemctl enable dbus


echo "[CHROOT] Creating WiFi configuration..."
mkdir -p /etc/NetworkManager/system-connections

cat <<EOF >/etc/NetworkManager/system-connections/Testpress_5G.nmconnection
[connection]
id=Testpress_5G
uuid=$(uuidgen)
type=wifi
autoconnect=true

[wifi]
ssid=Testpress_5G
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=Tp12345

[ipv4]
method=auto

[ipv6]
method=ignore
EOF

chmod 600 /etc/NetworkManager/system-connections/Testpress_5G.nmconnection


echo "[CHROOT] Creating kiosk user..."
useradd -m -s /bin/bash user
echo "user:user" | chpasswd


echo "[CHROOT] Setting LightDM autologin to LXDE..."
mkdir -p /etc/lightdm/lightdm.conf.d

cat <<EOF >/etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=user
autologin-session=LXDE
autologin-user-timeout=0
EOF


echo "[CHROOT] Creating LXDE autostart..."
mkdir -p /home/user/.config/lxsession/LXDE/

cat <<EOF >/home/user/.config/lxsession/LXDE/autostart
@xset s off
@xset -dpms
@xset s noblank

# NetworkManager will auto-connect to WiFi; no manual wpa_supplicant needed.

# Launch Chromium
@chromium https://lmsdemo.testpress.in
EOF


echo "[CHROOT] Fixing permissions..."
chown -R user:user /home/user/.config


echo "[CHROOT] DONE — LXDE desktop, WiFi autoconnect, LightDM autologin, Chromium autostart."

