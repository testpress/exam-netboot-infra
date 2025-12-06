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
echo "[1] Validating config + PXE files..."
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
    bsdtar \
    curl \
    ca-certificates \
    systemd-container \
    rsync

echo "[OK] All server + build dependencies installed."

echo ""
echo "=============================================="
echo "[3] Creating directory structure..."
echo "=============================================="
sudo mkdir -p /srv/tftp
sudo mkdir -p $TARGET_DIR/base
sudo mkdir -p $IPXE_DIR


echo ""
echo "=============================================="
echo "[4] Downloading iPXE bootloaders..."
echo "=============================================="
sudo wget -O /srv/tftp/ipxe.efi https://boot.ipxe.org/ipxe.efi
sudo wget -O /srv/tftp/undionly.kpxe https://boot.ipxe.org/undionly.kpxe

sudo chmod 644 /srv/tftp/ipxe.efi
sudo chmod 644 /srv/tftp/undionly.kpxe
echo "[OK] Downloaded ipxe.efi and undionly.kpxe"


echo ""
echo "=============================================="
echo "[5] Copying boot.ipxe + kiosk.cfg..."
echo "=============================================="
sudo cp "$PXE_DIR/boot.ipxe" $IPXE_DIR/
sudo cp "$PXE_DIR/kiosk.cfg" $TARGET_DIR/


echo ""
echo "=============================================="
echo "[6] Applying dnsmasq configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/dnsmasq.conf" /etc/dnsmasq.conf
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "[7] Downloading Debian ISO..."
echo "=============================================="

DEBIAN_ISO_URL="https://saimei.ftp.acc.umu.se/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
DEBIAN_ISO_PATH="/tmp/debian.iso"
DEBIAN_MOUNT="/mnt/debianiso"

wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
sudo mkdir -p "$DEBIAN_MOUNT"
sudo mount -o loop "$DEBIAN_ISO_PATH" "$DEBIAN_MOUNT"

echo "[OK] Debian ISO downloaded + mounted."

echo ""
echo "=============================================="
echo "[8] Extracting Debian kernel + initrd..."
echo "=============================================="

# Debian netinst stores kernel/initrd inside install.amd/
sudo cp "$DEBIAN_MOUNT/install.amd/vmlinuz" "$TARGET_DIR/vmlinuz"
sudo cp "$DEBIAN_MOUNT/install.amd/initrd.gz" "$TARGET_DIR/initrd.gz"

sudo umount "$DEBIAN_MOUNT"
rm -f "$DEBIAN_ISO_PATH"

echo "[OK] Kernel + initrd extracted to $TARGET_DIR"

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
echo "[11] Adding kiosk autostart..."
echo "=============================================="

sudo mkdir -p "$ROOTFS/etc/skel/.config/openbox"

cat <<EOF | sudo tee "$ROOTFS/etc/skel/.config/openbox/autostart"
#!/bin/bash
chromium --kiosk --noerrdialogs --incognito https://your-lms-url-here
EOF

sudo chmod +x "$ROOTFS/etc/skel/.config/openbox/autostart"

echo "[OK] Kiosk autostart configured."

echo ""
echo "=============================================="
echo "[12] Creating minimal.squashfs..."
echo "=============================================="

sudo mksquashfs "$ROOTFS" "$TARGET_DIR/minimal.squashfs" -comp xz -e boot

echo "[OK] minimal.squashfs built at $TARGET_DIR/minimal.squashfs"



echo ""
echo "=============================================="
echo "[9] Setting file permissions..."
echo "=============================================="
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html


echo ""
echo "=============================================="
echo "[10] Applying nginx configuration..."
echo "=============================================="
sudo cp "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/default


echo ""
echo "=============================================="
echo "[11] Restarting services..."
echo "=============================================="
sudo systemctl restart nginx
sudo systemctl restart dnsmasq


echo ""
echo "=============================================="
echo "          SETUP COMPLETE 🎉"
echo "=============================================="
echo "HTTP Server:  http://${SERVER_IP}:${HTTP_PORT}/"
echo "Boot Script:  http://${SERVER_IP}:${HTTP_PORT}/ipxe/boot.ipxe"
echo "Kernel:       $TARGET_DIR/vmlinuz"
echo "Initrd:       $TARGET_DIR/initrd.xz"
echo "Modules:      $TARGET_DIR/base/"
echo "kiosk.cfg:    $TARGET_DIR/kiosk.cfg"
echo ""
echo "PXE/iPXE + Porteus Kiosk boot server is READY."
echo ""

