#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

ISO_URL="https://static.testpress.in/netboot/Porteus-Kiosk-6.1.0-x86_64-customer_5446-FMSD.iso"
ISO_PATH="/tmp/porteus.iso"
MOUNT_DIR="/mnt/porteusiso"

TARGET_DIR="/var/www/html/porteus"
IPXE_DIR="/var/www/html/ipxe"

CONFIG_DIR="../config"
PXE_DIR="../pxe"

echo "=============================================="
echo "[1] Checking config + PXE files exist..."
echo "=============================================="

REQUIRED_FILES=(
    "$CONFIG_DIR/dnsmasq.conf"
    "$CONFIG_DIR/nginx.conf"
    "$PXE_DIR/boot.ipxe"
    "$PXE_DIR/kiosk.cfg"
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
echo "[2] Installing system packages..."
echo "=============================================="

sudo apt update -y
sudo apt install -y dnsmasq nginx wget curl


echo ""
echo "=============================================="
echo "[3] Applying nginx config (port ${HTTP_PORT})..."
echo "=============================================="

sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default
sudo systemctl restart nginx


echo ""
echo "=============================================="
echo "[4] Creating directory structure..."
echo "=============================================="

sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR/base
sudo mkdir -p $IPXE_DIR


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe + kiosk.cfg..."
echo "=============================================="

sudo cp "$PXE_DIR/boot.ipxe" $IPXE_DIR/
sudo cp "$PXE_DIR/kiosk.cfg" $TARGET_DIR/


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq config..."
echo "=============================================="

sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "[7] Downloading ISO..."
echo "=============================================="

wget -O "$ISO_PATH" "$ISO_URL"


echo ""
echo "=============================================="
echo "[8] Extracting ISO contents..."
echo "=============================================="

sudo mkdir -p "$MOUNT_DIR"
sudo mount -o loop "$ISO_PATH" "$MOUNT_DIR"

sudo cp "$MOUNT_DIR/boot/vmlinuz" "$TARGET_DIR/"
sudo cp "$MOUNT_DIR/boot/initrd.xz" "$TARGET_DIR/"
sudo cp "$MOUNT_DIR/porteus/base/"*.xzm "$TARGET_DIR/base/"

sudo umount "$MOUNT_DIR"
rm -f "$ISO_PATH"


echo ""
echo "=============================================="
echo "[9] Setting permissions..."
echo "=============================================="

sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html


echo ""
echo "=============================================="
echo "[10] Restarting services..."
echo "=============================================="

sudo systemctl restart nginx
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "              SETUP COMPLETE 🎉"
echo "=============================================="
echo "HTTP Server:  http://${SERVER_IP}:${HTTP_PORT}/"
echo "Boot Script:  http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:       $TARGET_DIR/vmlinuz"
echo "Initrd:       $TARGET_DIR/initrd.xz"
echo "Modules:      $TARGET_DIR/base/"
echo "kiosk.cfg:    $TARGET_DIR/kiosk.cfg"
echo ""
echo "READY FOR PXE BOOTING."
echo ""

