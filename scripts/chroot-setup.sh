#!/bin/bash
set -e

echo "[CHROOT] Updating package lists..."
apt update

echo "[CHROOT] Installing GUI + browser + network stack..."

apt install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    xinit \
    xinput \
    udev \
    openbox \
    lightdm \
    lightdm-gtk-greeter \
    chromium \
    wpasupplicant \
    wireless-tools \
    systemd-networkd \
    systemd-resolved \
    dbus-x11 \
    fonts-dejavu \
    fonts-liberation \
    libatk1.0-0t64 \
    libgtk-3-0 \
    libgdk-pixbuf-2.0-0 \
    libasound2 \
    libnss3 \
    mesa-utils


echo "[CHROOT] Enabling network services..."
systemctl enable systemd-networkd
systemctl enable systemd-resolved


echo "[CHROOT] Creating WiFi config..."

mkdir -p /etc/wpa_supplicant

cat <<EOF >/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
ctrl_interface=/run/wpa_supplicant
network={
    ssid="Testpress_5G"
    psk="Tp12345"
}
EOF

chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf


echo "[CHROOT] Creating systemd-networkd config for WLAN..."

mkdir -p /etc/systemd/network

cat <<EOF >/etc/systemd/network/25-wireless.network
[Match]
Name=wlan0

[Network]
DHCP=yes
EOF


echo "[CHROOT] Creating kiosk user..."
useradd -m -s /bin/bash user
echo "user:user" | chpasswd


echo "[CHROOT] Creating Openbox desktop session..."

mkdir -p /usr/share/xsessions
cat <<EOF >/usr/share/xsessions/openbox.desktop
[Desktop Entry]
Name=Openbox
Exec=openbox-session
Type=XSession
EOF


echo "[CHROOT] Setting up autologin..."

mkdir -p /etc/lightdm/lightdm.conf.d
cat <<EOF >/etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=user
user-session=openbox
autologin-user-timeout=0
EOF


echo "[CHROOT] Creating Openbox config..."

mkdir -p /home/user/.config/openbox

cat <<EOF >/home/user/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <desktops><number>1</number></desktops>
</openbox_config>
EOF


echo "[CHROOT] Creating autostart script (Non-kiosk browser)..."

cat <<EOF >/home/user/.config/openbox/autostart
#!/bin/bash

# Connect WiFi
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Launch Chromium normally
chromium https://lmsdemo.testpress.in &
EOF

chmod +x /home/user/.config/openbox/autostart
chown -R user:user /home/user/.config


echo "[CHROOT] DONE: GUI, WiFi, browser, autologin configured."

