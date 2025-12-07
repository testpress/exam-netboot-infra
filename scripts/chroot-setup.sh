#!/bin/bash
set -e

echo "[CHROOT] Updating package lists..."
apt update

echo "[CHROOT] Installing GUI base + runtime dependencies..."

apt install -y --no-install-recommends \
    xorg \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-video-fbdev \
    openbox \
    obconf \
    lightdm \
    lightdm-gtk-greeter \
    dbus-x11 \
    polkitd \
    pkexec \
    chromium \
    fonts-dejavu \
    fonts-liberation \
    libnss3 \
    libatk1.0-0t64 \
    libgdk-pixbuf-2.0-0 \
    libgtk-3-0 \
    libasound2 \
    mesa-utils


echo "[CHROOT] Creating kiosk user..."
useradd -m -s /bin/bash user
echo "user:user" | chpasswd


echo "[CHROOT] Creating Openbox session files..."

# Create X session entry so LightDM knows Openbox is a desktop session
mkdir -p /usr/share/xsessions
cat <<EOF >/usr/share/xsessions/openbox-kiosk.desktop
[Desktop Entry]
Name=Openbox Kiosk
Comment=Minimal Openbox session running a browser
Exec=/usr/bin/openbox-session
TryExec=/usr/bin/openbox-session
Type=Application
EOF


echo "[CHROOT] Configuring autologin for LightDM..."

mkdir -p /etc/lightdm/lightdm.conf.d
cat <<EOF >/etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=user
autologin-session=openbox-kiosk
autologin-user-timeout=0
EOF


echo "[CHROOT] Setting default Openbox config..."

mkdir -p /home/user/.config/openbox

# rc.xml = window behavior
cat <<EOF >/home/user/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <theme>
    <name>Clearlooks</name>
  </theme>
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF

# menu.xml = disable right-click menu
cat <<EOF >/home/user/.config/openbox/menu.xml
<openbox_menu>
</openbox_menu>
EOF


echo "[CHROOT] Creating .xinitrc..."

cat <<EOF >/home/user/.xinitrc
#!/bin/bash
exec openbox-session
EOF

chmod +x /home/user/.xinitrc


echo "[CHROOT] Creating Openbox autostart (Chromium kiosk)..."

cat <<EOF >/home/user/.config/openbox/autostart
#!/bin/bash

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Chromium kiosk
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
chown -R user:user /home/user/.config
chown user:user /home/user/.xinitrc


echo "[CHROOT] GUI + Openbox session + kiosk initialization COMPLETE."

