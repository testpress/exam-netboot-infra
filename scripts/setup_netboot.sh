#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

# Lubuntu 26.04 ISO (cached)
LUBUNTU_ISO_URL="https://cdimage.ubuntu.com/lubuntu/releases/26.04/snapshot1/lubuntu-26.04-desktop-amd64.iso"
LUBUNTU_ISO_PATH="/opt/lubuntu-26.04.iso"
LUBUNTU_MOUNT="/mnt/lubuntuiso"

# PXE directories
TARGET_DIR="/var/www/html/lubuntu"
IPXE_DIR="/var/www/html/ipxe"

# Config directories
CONFIG_DIR="../config"
PXE_DIR="../pxe"

# Build directory for rootfs (chroot)
BUILD_DIR="$HOME/lubuntu"
ROOTFS="$BUILD_DIR/rootfs"

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
echo "[2] Installing required server packages..."
echo "=============================================="

sudo apt update -y
sudo apt install -y \
    dnsmasq \
    nginx \
    wget \
    debootstrap \
    squashfs-tools \
    xz-utils \
    curl \
    ca-certificates \
    systemd-container \
    rsync

echo "[OK] All dependencies installed."


echo ""
echo "=============================================="
echo "[3] Creating directory structure..."
echo "=============================================="

sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR
sudo mkdir -p $IPXE_DIR
sudo mkdir -p $LUBUNTU_MOUNT
mkdir -p $BUILD_DIR

echo "[OK] Directory layout ready."


echo ""
echo "=============================================="
echo "[4] Downloading iPXE bootloaders..."
echo "=============================================="

sudo wget -O /srv/tftp/ipxe.efi https://boot.ipxe.org/ipxe.efi
sudo wget -O /srv/tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe

sudo chmod 644 /srv/tftp/ipxe.efi
sudo chmod 644 /srv/tftp/undionly.kpxe

echo "[OK] iPXE bootloaders installed."


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe..."
echo "=============================================="

sudo cp "$PXE_DIR/boot.ipxe" "$IPXE_DIR/"

echo "[OK] boot.ipxe copied."


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq configuration..."
echo "=============================================="

sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq

echo "[OK] dnsmasq updated."


echo ""
echo "=============================================="
echo "[7] Fetching Lubuntu 26.04 ISO (cached)..."
echo "=============================================="

if [ -f "$LUBUNTU_ISO_PATH" ]; then
    echo "[OK] Using existing ISO: $LUBUNTU_ISO_PATH"
else
    echo "[*] Downloading Lubuntu ISO..."
    sudo wget -O "$LUBUNTU_ISO_PATH" "$LUBUNTU_ISO_URL"
fi

sudo mkdir -p "$LUBUNTU_MOUNT"
sudo mount -o loop "$LUBUNTU_ISO_PATH" "$LUBUNTU_MOUNT"

echo "[OK] ISO mounted."


echo ""
echo "=============================================="
echo "[8] Extracting kernel + initrd..."
echo "=============================================="

sudo cp "$LUBUNTU_MOUNT/casper/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$LUBUNTU_MOUNT/casper/initrd" "$TARGET_DIR/initrd"

sudo umount "$LUBUNTU_MOUNT"

echo "[OK] Kernel + initrd extracted."


echo ""
echo "=============================================="
echo "[9] Building minimal rootfs (stored in HOME)..."
echo "=============================================="

sudo rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

sudo debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

echo "[OK] Minimal Lubuntu/Ubuntu rootfs created at $ROOTFS."


echo ""
echo "=============================================="
echo "[10] Creating minimal.squashfs..."
echo "=============================================="

sudo mksquashfs "$ROOTFS" "$TARGET_DIR/minimal.squashfs" -comp xz -e boot

echo "[OK] minimal.squashfs created."


echo ""
echo "=============================================="
echo "[11] Setting file permissions..."
echo "=============================================="

sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

echo "[OK] Permissions applied."


echo ""
echo "=============================================="
echo "[12] Applying nginx configuration..."
echo "=============================================="

sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default
sudo systemctl restart nginx

echo "[OK] nginx updated."


echo ""
echo "=============================================="
echo "        LUBUNTU PXE SETUP COMPLETE 🚀"
echo "=============================================="
echo "PXE Boot URL:  http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:        $TARGET_DIR/vmlinuz"
echo "Initrd:        $TARGET_DIR/initrd"
echo "SquashFS:      $TARGET_DIR/minimal.squashfs"
echo ""
echo "Boot now to validate minimal Lubuntu PXE load."

