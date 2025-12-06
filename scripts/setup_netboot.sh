#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

# ✅ Lubuntu 24.04.1 LTS LIVE ISO
LUBUNTU_ISO_URL="https://cdimage.ubuntu.com/lubuntu/releases/questing/release/lubuntu-25.10-desktop-amd64.iso"
LUBUNTU_ISO_PATH="/opt/lubuntu-live.iso"
LUBUNTU_MOUNT="/mnt/lubuntu"

TARGET_DIR="/var/www/html/lubuntu"
IPXE_DIR="/var/www/html/ipxe"

CONFIG_DIR="../config"
PXE_DIR="../pxe"

echo "=============================================="
echo "[1] Validating config + PXE files..."
echo "=============================================="

REQUIRED_FILES=(
    "$CONFIG_DIR/dnsmasq.conf"
    "$CONFIG_DIR/nginx.conf"
    "$PXE_DIR/boot.ipxe"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "[ERROR] Missing file: $file"
        exit 1
    fi
done
echo "[OK] All config + PXE files found."


echo ""
echo "=============================================="
echo "[2] Installing required packages..."
echo "=============================================="
sudo apt update -y
sudo apt install -y \
    dnsmasq \
    nginx \
    wget \
    squashfs-tools \
    xorriso

echo "[OK] Server build dependencies installed."


echo ""
echo "=============================================="
echo "[3] Creating directories..."
echo "=============================================="
sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR
sudo mkdir -p $IPXE_DIR
sudo mkdir -p $LUBUNTU_MOUNT


echo ""
echo "=============================================="
echo "[4] Downloading iPXE bootloaders..."
echo "=============================================="

sudo wget -O /srv/tftp/ipxe.efi https://boot.ipxe.org/ipxe.efi
sudo wget -O /srv/tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe

sudo chmod 644 /srv/tftp/ipxe.efi
sudo chmod 644 /srv/tftp/undionly.kpxe

echo "[OK] iPXE downloaded."


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe..."
echo "=============================================="
sudo cp "$PXE_DIR/boot.ipxe" $IPXE_DIR/
echo "[OK] boot.ipxe copied."


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq config..."
echo "=============================================="
sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "[7] Fetching Lubuntu LIVE ISO..."
echo "=============================================="

if [ -f "$LUBUNTU_ISO_PATH" ]; then
    echo "[OK] Using cached ISO at $LUBUNTU_ISO_PATH"
else
    echo "[*] Downloading Lubuntu LIVE ISO..."
    sudo wget -O "$LUBUNTU_ISO_PATH" "$LUBUNTU_ISO_URL"
fi

sudo mount -o loop "$LUBUNTU_ISO_PATH" "$LUBUNTU_MOUNT"
echo "[OK] LIVE ISO mounted."


echo ""
echo "=============================================="
echo "[8] Extracting kernel + initrd + squashfs..."
echo "=============================================="

sudo cp "$LUBUNTU_MOUNT/casper/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$LUBUNTU_MOUNT/casper/initrd" "$TARGET_DIR/initrd"
sudo cp "$LUBUNTU_MOUNT/casper/filesystem.squashfs" "$TARGET_DIR/filesystem.squashfs"

sudo umount "$LUBUNTU_MOUNT"

echo "[OK] Lubuntu boot files extracted."


echo ""
echo "=============================================="
echo "[9] Patch filesystem.squashfs (GUI → Chromium Kiosk)"
echo "=============================================="

WORKDIR="/tmp/lubuntu-root"
sudo rm -rf "$WORKDIR"
sudo unsquashfs -d "$WORKDIR" "$TARGET_DIR/filesystem.squashfs"

# REMOVE FULL DESKTOP (optional)
sudo chroot "$WORKDIR" apt remove --purge -y lxqt* lubuntu-desktop

# INSTALL CHROMIUM + OPENBOX
sudo chroot "$WORKDIR" apt install -y chromium-browser openbox xserver-xorg-legacy

# AUTOLOGIN
mkdir -p "$WORKDIR/etc/systemd/system/getty@tty1.service.d"
cat <<EOF | sudo tee "$WORKDIR/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ubuntu --noclear %I \$TERM
EOF

# OPENBOX AUTOSTART
mkdir -p "$WORKDIR/home/ubuntu/.config/openbox"
cat <<EOF | sudo tee "$WORKDIR/home/ubuntu/.config/openbox/autostart"
chromium-browser --kiosk --noerrdialogs --incognito https://your-lms-url
EOF

sudo chmod +x "$WORKDIR/home/ubuntu/.config/openbox/autostart"

# .xinitrc
echo "exec openbox-session" | sudo tee "$WORKDIR/home/ubuntu/.xinitrc"

echo "[OK] Chromium kiosk patched."


echo ""
echo "=============================================="
echo "[10] Rebuilding filesystem.squashfs..."
echo "=============================================="
sudo mksquashfs "$WORKDIR" "$TARGET_DIR/filesystem.squashfs" -comp xz
echo "[OK] squashfs rebuilt."


echo ""
echo "=============================================="
echo "[11] Permissions..."
echo "=============================================="
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html


echo ""
echo "=============================================="
echo "[12] Apply nginx config + restart services..."
echo "=============================================="
sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default
sudo systemctl restart nginx
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "            SETUP COMPLETE 🎉"
echo "=============================================="
echo "PXE Boot:"
echo "  Kernel:       $TARGET_DIR/vmlinuz"
echo "  Initrd:       $TARGET_DIR/initrd"
echo "  RootFS:       $TARGET_DIR/filesystem.squashfs"
echo "iPXE Script:    http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo ""

