#!/bin/bash
set -e

echo "[CHROOT] Fixing apt sources (Debian 13 stable)..."
cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian stable main contrib non-free-firmware
deb http://security.debian.org/debian-security stable-security main contrib non-free-firmware
deb http://deb.debian.org/debian stable-updates main contrib non-free-firmware
EOF


echo "[CHROOT] Updating package index..."
apt update || (echo "APT FAILED — DNS or sources not working" && exit 1)


echo "[CHROOT] Installing core GUI stack, input, WiFi, browser..."
apt install -y --no-install-recommends \
    # Xorg minimal core + input
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    xinit \
    xinput \
    udev \
    # Desktop
    openbox \
    lightdm \
    lightdm-gtk-greeter \
    dbus-x11 \
    # Browser
    chromium \
    # Networking
    wpasupplicant \
    wireless-tools \
    systemd \
    dbus \
    # Fonts
    fonts-dejavu \
    fonts-liberation \
    # Browser deps
    libatk1.0-0t64 \
    libgdk-pixbuf-2.0-0 \
    libgtk-3-0 \
    libasound2 \
    libnss3 \
    # Graphics util
    mesa-utils


echo "[CHROOT] Enabling required system services..."
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service


echo "[CHROOT] Creating WiFi configuration..."
mkdir -p /etc/wpa_supplicant

cat <<EOF >/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
ctrl_interface=/run/wpa_supplicant

network={
    ssid="Testpress_5G"
    psk="Tp12345"
    key_mgmt=WPA-PSK
}
EOF

chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf


echo "[CHROOT] Adding systemd-networkd WLAN config..."
mkdir -p /etc/systemd/network

cat <<EOF >/etc/systemd/network/20-wlan0.network
[Match]
Name=wlan0

[Network]
DHCP=yes
EOF


echo "[CHROOT] Creating kiosk user..."
useradd -m -s /bin/bash user
echo "user:user" | chpasswd


echo "[CHROOT] Configuring LightDM autologin..."
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

echo "<openbox_menu></openbox_menu>" > /home/user/.config/openbox/menu.xml


echo "[CHROOT] Creating .xinitrc..."
cat <<EOF >/home/user/.xinitrc
#!/bin/bash
exec openbox-session
EOF
chmod +x /home/user/.xinitrc


echo "[CHROOT] Creating Openbox autostart script..."
cat <<EOF >/home/user/.config/openbox/autostart
#!/bin/bash

# Connect WiFi
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Launch Chromium (normal mode)
chromium https://lmsdemo.testpress.in &
EOF

chmod +x /home/user/.config/openbox/autostart
chown -R user:user /home/user/.config
chown user:user /home/user/.xinitrc


echo "[CHROOT] Done: Full GUI, WiFi, Chromium setup completed successfully."

