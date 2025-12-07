#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

DEBIAN_ISO_URL="https://saimei.ftp.acc.umu.se/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.2.0-amd64-standard.iso"
DEBIAN_ISO_PATH="/opt/debian-live.iso"
DEBIAN_MOUNT="/mnt/debianiso"

TARGET_DIR="/var/www/html/debian"
IPXE_DIR="/var/www/html/ipxe"

CONFIG_DIR="../config"
PXE_DIR="../pxe"
CHROOT_SETUP="./chroot-setup.sh"   # <— Your external script


echo "=============================================="
echo "[1] Validating config + PXE files..."
echo "=============================================="

REQUIRED_FILES=(
    "$CONFIG_DIR/dnsmasq.conf"
    "$CONFIG_DIR/nginx.conf"
    "$PXE_DIR/boot.ipxe"
    "$CHROOT_SETUP"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "[ERROR] Missing file: $file"
        exit 1
    fi
done


echo ""
echo "=============================================="
echo "[2] Installing server packages..."
echo "=============================================="
sudo apt update -y
sudo apt install -y \
    dnsmasq \
    nginx \
    wget \
    debootstrap \
    squashfs-tools \
    xz-utils \
    xorriso \
    curl \
    ca-certificates \
    systemd-container \
    rsync


echo ""
echo "=============================================="
echo "[3] Creating directory structure..."
echo "=============================================="
sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR
sudo mkdir -p $IPXE_DIR
sudo mkdir -p $DEBIAN_MOUNT


echo ""
echo "=============================================="
echo "[4] Downloading iPXE bootloaders..."
echo "=============================================="
sudo wget -O /srv/tftp/ipxe.efi https://boot.ipxe.org/ipxe.efi
sudo wget -O /srv/tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe
sudo chmod 644 /srv/tftp/*


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe..."
echo "=============================================="
sudo cp "$PXE_DIR/boot.ipxe" $IPXE_DIR/


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq config..."
echo "=============================================="
sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "[7] Fetching Debian LIVE ISO (cached)..."
echo "=============================================="

if [ -f "$DEBIAN_ISO_PATH" ]; then
    echo "[OK] Reusing cached ISO"
else
    sudo wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
fi

sudo mount -o loop "$DEBIAN_ISO_PATH" "$DEBIAN_MOUNT"


echo ""
echo "=============================================="
echo "[8] Extracting live kernel + initrd..."
echo "=============================================="
sudo cp "$DEBIAN_MOUNT/live/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$DEBIAN_MOUNT/live/initrd.img" "$TARGET_DIR/initrd.img"
sudo umount "$DEBIAN_MOUNT"


echo ""
echo "=============================================="
echo "[9] Building Debian minimal rootfs..."
echo "=============================================="

ROOTFS="/tmp/debian-rootfs"

sudo umount -l "$ROOTFS/proc" || true
sudo umount -l "$ROOTFS/sys" || true
sudo umount -l "$ROOTFS/dev" || true

sudo mkdir -p "$ROOTFS"

sudo debootstrap --variant=minbase stable "$ROOTFS" http://deb.debian.org/debian


echo ""
echo "=============================================="
echo "[10] Running GUI + kiosk setup in chroot..."
echo "=============================================="

sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /proc "$ROOTFS/proc"
sudo mount --bind /sys "$ROOTFS/sys"
sudo cp /etc/resolv.conf "$ROOTFS/etc/"

sudo cp "$CHROOT_SETUP" "$ROOTFS/root/chroot-setup.sh"
sudo chmod +x "$ROOTFS/root/chroot-setup.sh"

sudo chroot "$ROOTFS" /bin/bash /root/chroot-setup.sh

sudo umount "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys"


echo ""
echo "=============================================="
echo "[11] Creating minimal.squashfs..."
echo "=============================================="
sudo mksquashfs "$ROOTFS" "$TARGET_DIR/minimal.squashfs" -comp xz -e boot


echo ""
echo "=============================================="
echo "[12] Setting permissions..."
echo "=============================================="
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html


echo ""
echo "=============================================="
echo "[13] Applying nginx configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default
sudo systemctl restart nginx


echo ""
echo "=============================================="
echo "        SETUP COMPLETE 🚀"
echo "=============================================="
echo "PXE Boot:     http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:       $TARGET_DIR/vmlinuz"
echo "Initrd:       $TARGET_DIR/initrd.img"
echo "SquashFS:     $TARGET_DIR/minimal.squashfs"

