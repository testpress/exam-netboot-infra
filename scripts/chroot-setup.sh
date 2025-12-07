#!/bin/bash
set -e

echo "[CHROOT] Updating package lists..."
apt update

echo "[CHROOT] Installing GUI base + input stack + runtime dependencies..."

apt install -y --no-install-recommends \
    # Xorg Core + Drivers
    xorg \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    xinput \
    udev \
    # WM + Display Manager
    openbox \
    obconf \
    lightdm \
    lightdm-gtk-greeter \
    dbus-x11 \
    # Privilege Runtime
    polkitd \
    pkexec \
    # Browser
    chromium \
    # Fonts
    fonts-dejavu \
    fonts-liberation \
    # Browser dependencies
    libnss3 \
    libatk1.0-0t64 \
    libgdk-pixbuf-2.0-0 \
    libgtk-3-0 \
    libasound2 \
    mesa-utils

echo "[CHROOT] GUI packages installed."


echo "[CHROOT] Enabling udev for input devices..."
systemctl enable systemd-udevd.service
systemctl enable systemd-udev-trigger.service


echo "[CHROOT] Creating kiosk user..."
useradd -m -s /bin/bash user
echo "user:user" | chpasswd


echo "[CHROOT] Creating Openbox session descriptor..."

mkdir -p /usr/share/xsessions
cat <<EOF >/usr/share/xsessions/openbox-kiosk.desktop
[Desktop Entry]
Name=Openbox Kiosk
Comment=Minimal Openbox session running a browser
Exec=/usr/bin/openbox-session
TryExec=/usr/bin/openbox-session
Type=Application
EOF


echo "[CHROOT] Configuring LightDM autologin..."

mkdir -p /etc/lightdm/lightdm.conf.d
cat <<EOF >/etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=user
autologin-session=openbox-kiosk
autologin-user-timeout=0
EOF


echo "[CHROOT] Setting default Openbox configuration..."

mkdir -p /home/user/.config/openbox

# rc.xml — minimal behavior
cat <<EOF >/home/user/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <theme><name>Clearlooks</name></theme>
  <desktops><number>1</number></desktops>
</openbox_config>
EOF

# Empty menu (disable right-click)
cat <<EOF >/home/user/.config/openbox/menu.xml
<openbox_menu></openbox_menu>
EOF


echo "[CHROOT] Creating .xinitrc..."

cat <<EOF >/home/user/.xinitrc
#!/bin/bash
exec openbox-session
EOF
chmod +x /home/user/.xinitrc


echo "[CHROOT] Creating Openbox autostart (Chromium Kiosk)..."

cat <<EOF >/home/user/.config/openbox/autostart
#!/bin/bash

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Chromium kiosk mode
chromium \
  --kiosk \
  --incognito \
  --noerrdialogs \
  --disable-infobars \
  --start-maximized \
  --no-first-run \
  --disable-features=TranslateUI \
  https://your-lms-url-here
EOF

chmod +x /home/user/.config/openbox/autostart


echo "[CHROOT] Fixing permissions..."
chown -R user:user /home/user/.config
chown user:user /home/user/.xinitrc


echo "[CHROOT] COMPLETED: GUI stack, input drivers, LightDM autologin, Openbox kiosk, Chromium kiosk."

