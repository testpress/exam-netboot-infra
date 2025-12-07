#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

# Debian Live LXDE ISO (cached)
ISO_URL="https://laotzu.ftp.acc.umu.se/mirror/cdimage/archive/12.7.0-live/amd64/iso-hybrid/debian-live-12.7.0-amd64-lxde.iso"
ISO_PATH="/opt/debian-live-lxde.iso"
ISO_MOUNT="/mnt/debianlive"

TARGET_DIR="/var/www/html/debian"
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

echo "[OK] All config files found."


echo ""
echo "=============================================="
echo "[2] Installing server dependencies..."
echo "=============================================="
sudo apt update -y
sudo apt install -y \
    dnsmasq \
    nginx \
    wget \
    xorriso \
    curl \
    ca-certificates \
    rsync

echo "[OK] Dependencies installed."


echo ""
echo "=============================================="
echo "[3] Preparing directories..."
echo "=============================================="
sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR
sudo mkdir -p $IPXE_DIR
sudo mkdir -p $ISO_MOUNT

echo "[OK] Directory structure ready."


echo ""
echo "=============================================="
echo "[4] Downloading iPXE bootloaders..."
echo "=============================================="
sudo wget -O /srv/tftp/ipxe.efi https://boot.ipxe.org/ipxe.efi
sudo wget -O /srv/tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe
sudo chmod 644 /srv/tftp/ipxe.efi /srv/tftp/undionly.kpxe

echo "[OK] iPXE bootloaders downloaded."


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe..."
echo "=============================================="
sudo cp "$PXE_DIR/boot.ipxe" "$IPXE_DIR/"

echo "[OK] boot.ipxe placed."


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq

echo "[OK] dnsmasq restarted."


echo ""
echo "=============================================="
echo "[7] Fetching Debian Live LXDE ISO (cached)..."
echo "=============================================="
if [ -f "$ISO_PATH" ]; then
    echo "[OK] Using existing ISO $ISO_PATH"
else
    sudo wget -O "$ISO_PATH" "$ISO_URL"
fi

echo "[OK] ISO ready."


echo ""
echo "=============================================="
echo "[8] Mounting ISO..."
echo "=============================================="
sudo mount -o loop "$ISO_PATH" "$ISO_MOUNT"

echo "[OK] ISO mounted."


echo ""
echo "=============================================="
echo "[9] Extracting kernel + initrd + squashfs..."
echo "=============================================="
sudo cp "$ISO_MOUNT/live/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$ISO_MOUNT/live/initrd.img" "$TARGET_DIR/initrd.img"
sudo cp "$ISO_MOUNT/live/filesystem.squashfs" "$TARGET_DIR/filesystem.squashfs"

sudo umount "$ISO_MOUNT"

echo "[OK] Kernel, initrd and squashfs prepared."


echo ""
echo "=============================================="
echo "[10] Setting permissions..."
echo "=============================================="
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

echo "[OK] Permissions set."


echo ""
echo "=============================================="
echo "[11] Applying nginx config..."
echo "=============================================="
sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default
sudo systemctl restart nginx

echo "[OK] nginx restarted."


echo ""
echo "=============================================="
echo "         SETUP COMPLETE 🎯"
echo "=============================================="
echo "PXE Boot URL:     http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:           $TARGET_DIR/vmlinuz"
echo "Initrd:           $TARGET_DIR/initrd.img"
echo "SquashFS:         $TARGET_DIR/filesystem.squashfs"
echo ""

