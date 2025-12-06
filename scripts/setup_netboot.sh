#!/bin/bash
set -e

SERVER_IP="10.0.0.1"
HTTP_PORT="9000"

DEBIAN_ISO_URL="https://saimei.ftp.acc.umu.se/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
DEBIAN_ISO_PATH="/opt/debian-netinst.iso"
DEBIAN_MOUNT="/mnt/debianiso"

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
echo "[OK] All config + PXE files found."


echo ""
echo "=============================================="
echo "[2] Installing required system packages..."
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

echo "[OK] Server build dependencies installed."


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

sudo chmod 644 /srv/tftp/ipxe.efi
sudo chmod 644 /srv/tftp/undionly.kpxe
echo "[OK] iPXE bootloaders downloaded."


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe..."
echo "=============================================="
sudo cp "$PXE_DIR/boot.ipxe" $IPXE_DIR/
echo "[OK] boot.ipxe copied."


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "[7] Fetching Debian ISO (cached)..."
echo "=============================================="

if [ -f "$DEBIAN_ISO_PATH" ]; then
    echo "[OK] Reusing cached ISO at $DEBIAN_ISO_PATH"
else
    echo "[*] Downloading Debian ISO..."
    sudo wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
fi

sudo mount -o loop "$DEBIAN_ISO_PATH" "$DEBIAN_MOUNT"
echo "[OK] ISO mounted."


echo ""
echo "=============================================="
echo "[8] Extracting Debian kernel + initrd..."
echo "=============================================="

sudo cp "$DEBIAN_MOUNT/install.amd/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$DEBIAN_MOUNT/install.amd/initrd.gz" "$TARGET_DIR/initrd.gz"

sudo umount "$DEBIAN_MOUNT"

echo "[OK] Kernel + initrd extracted."


echo ""
echo "=============================================="
echo "[9] Building Debian minimal rootfs..."
echo "=============================================="

ROOTFS="/tmp/debian-rootfs"
sudo rm -rf "$ROOTFS"
sudo mkdir -p "$ROOTFS"

sudo debootstrap --variant=minbase stable "$ROOTFS" http://deb.debian.org/debian
echo "[OK] Base rootfs created."


echo ""
echo "=============================================="
echo "[10] Installing Xorg, Openbox, Chromium..."
echo "=============================================="

sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /proc "$ROOTFS/proc"
sudo mount --bind /sys "$ROOTFS/sys"

sudo cp /etc/resolv.conf "$ROOTFS/etc/"

sudo chroot "$ROOTFS" /bin/bash <<EOF
apt update
apt install -y --no-install-recommends \
    xorg openbox chromium fonts-dejavu
EOF

sudo umount "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys"

echo "[OK] GUI stack + browser installed."


echo ""
echo "=============================================="
echo "[11] Adding Openbox kiosk autostart..."
echo "=============================================="

sudo mkdir -p "$ROOTFS/etc/skel/.config/openbox"

cat <<EOF | sudo tee "$ROOTFS/etc/skel/.config/openbox/autostart"
#!/bin/bash
chromium --kiosk --noerrdialogs --incognito https://your-lms-url
EOF

sudo chmod +x "$ROOTFS/etc/skel/.config/openbox/autostart"

echo "[OK] Kiosk launch script added."


echo ""
echo "=============================================="
echo "[12] Building minimal.squashfs..."
echo "=============================================="

sudo mksquashfs "$ROOTFS" "$TARGET_DIR/minimal.squashfs" -comp xz -e boot
echo "[OK] squashfs built."


echo ""
echo "=============================================="
echo "[13] Setting permissions..."
echo "=============================================="
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html


echo ""
echo "=============================================="
echo "[14] Applying nginx configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default


echo ""
echo "=============================================="
echo "[15] Restarting nginx + dnsmasq..."
echo "=============================================="
sudo systemctl restart nginx
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "            SETUP COMPLETE 🎉"
echo "=============================================="
echo "HTTP Server:  http://${SERVER_IP}:${HTTP_PORT}/"
echo "PXE Script:   http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:       $TARGET_DIR/vmlinuz"
echo "Initrd:       $TARGET_DIR/initrd.gz"
echo "SquashFS:     $TARGET_DIR/minimal.squashfs"
echo ""

