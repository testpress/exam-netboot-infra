#!/bin/bash
set -e

PXE_IP="192.168.1.160"
NET_RANGE="192.168.1.0/24"
IFACE="enp0s31f6"

ISO_NAME="ubuntu-24.04.3-desktop-amd64.iso"
ISO_URL="https://releases.ubuntu.com/24.04/${ISO_NAME}"

DOWNLOAD_DIR="/opt/pxe-downloads"
ISO_PATH="${DOWNLOAD_DIR}/${ISO_NAME}"

echo "=== STEP 1: Create download directory ==="
sudo mkdir -p "$DOWNLOAD_DIR"
sudo chmod 755 "$DOWNLOAD_DIR"

echo "=== STEP 2: Install required packages ==="
sudo apt update
sudo apt install -y \
    apache2 \
    nfs-kernel-server \
    dnsmasq \
    unzip \
    wget

echo "=== STEP 3: Create TFTP / Web folders ==="
sudo mkdir -p /var/lib/tftpboot/{bios,boot/casper,grub}
sudo mkdir -p /var/www/html/desktop/u2404

echo "=== STEP 4: Download Ubuntu ISO (cached) ==="
if [ -f "$ISO_PATH" ]; then
    echo "[OK] Reusing existing ISO: $ISO_PATH"
else
    echo "[*] Downloading Ubuntu Desktop ISO..."
    sudo wget -O "$ISO_PATH" "$ISO_URL"
fi

echo "=== STEP 5: Mount ISO ==="
sudo mount -o loop "$ISO_PATH" /media

echo "=== STEP 6: Copy ISO filesystem to webroot ==="
sudo cp -rf /media/* /var/www/html/desktop/u2404
sudo cp -rf /media/.disk /var/www/html/desktop/u2404

echo "=== STEP 7: Copy kernel + initrd to TFTP ==="
sudo cp /var/www/html/desktop/u2404/casper/vmlinuz /var/lib/tftpboot/boot/casper/
sudo cp /var/www/html/desktop/u2404/casper/initrd /var/lib/tftpboot/boot/casper/

sudo umount /media

echo "=== STEP 8: Download Syslinux (PXELinux BIOS) ==="
cd "$DOWNLOAD_DIR"
wget -nc https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.zip
unzip -o syslinux-6.03.zip

echo "=== STEP 9: Install Syslinux files ==="
sudo cp bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot/bios/
sudo cp bios/com32/libutil/libutil.c32 /var/lib/tftpboot/bios/
sudo cp bios/com32/menu/menu.c32 /var/lib/tftpboot/bios/
sudo cp bios/com32/menu/vesamenu.c32 /var/lib/tftpboot/bios/
sudo cp bios/core/pxelinux.0 /var/lib/tftpboot/bios/
sudo cp bios/core/lpxelinux.0 /var/lib/tftpboot/bios/

echo "=== STEP 10: Download UEFI GRUB + Shim packages ==="
wget -nc https://mirrors.kernel.org/ubuntu/pool/main/s/shim-signed/shim-signed_1.58+15.8-0ubuntu1_amd64.deb
wget -nc https://mirrors.kernel.org/ubuntu/pool/main/g/grub2/grub-efi-amd64-signed_1.202.5+2.12-1ubuntu7.3_amd64.deb

dpkg -x shim-signed_*.deb shim
dpkg -x grub-efi-amd64-signed_*.deb grub

sudo cp grub/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed \
    /var/lib/tftpboot/grub/grubx64.efi

sudo cp shim/usr/lib/shim/shimx64.efi.signed \
    /var/lib/tftpboot/grub/bootx64.efi

echo "=== STEP 11: Create symlink for BIOS ==="
sudo ln -sf /var/lib/tftpboot/boot /var/lib/tftpboot/bios/boot

echo "=== STEP 12: Configure NFS ==="
echo "/var/www/html/desktop ${NET_RANGE}(ro)" | sudo tee /etc/exports
sudo exportfs -ra

echo "=== STEP 13: Configure dnsmasq ==="
sudo bash -c "cat >/etc/dnsmasq.d/pxe.conf" <<EOF
interface=${IFACE}
bind-interfaces

dhcp-range=192.168.1.170,192.168.1.200,12h

dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,grub/bootx64.efi
dhcp-boot=/bios/pxelinux.0

enable-tftp
tftp-root=/var/lib/tftpboot

dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1

log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF

sudo systemctl restart dnsmasq

echo "=== STEP 14: BIOS PXELinux Menu ==="
sudo mkdir -p /var/lib/tftpboot/bios/pxelinux.cfg
sudo bash -c "cat >/var/lib/tftpboot/bios/pxelinux.cfg/default" <<EOF
DEFAULT menu.c32
MENU TITLE Ubuntu PXE Boot Menu

LABEL Ubuntu Desktop 24.04
  MENU LABEL Ubuntu Desktop 24.04
  KERNEL /boot/casper/vmlinuz
  APPEND initrd=/boot/casper/initrd boot=casper ip=dhcp netboot=nfs nfsroot=${PXE_IP}:/var/www/html/desktop/u2404
EOF

echo "=== STEP 15: UEFI GRUB Menu ==="
sudo bash -c "cat >/var/lib/tftpboot/grub/grub.cfg" <<EOF
if loadfont /grub/font.pf2 ; then
    set gfxmode=auto
    insmod efi_gop
    insmod gfxterm
    terminal_output gfxterm
fi

set timeout=5

menuentry "Ubuntu Desktop 24.04" {
    linux /boot/casper/vmlinuz boot=casper ip=dhcp netboot=nfs nfsroot=${PXE_IP}:/var/www/html/desktop/u2404
    initrd /boot/casper/initrd
}
EOF

echo "=== STEP 16: Restart Services ==="
sudo systemctl restart apache2
sudo systemctl restart nfs-kernel-server
sudo systemctl restart dnsmasq

echo "=== PXE SERVER READY 🚀 ==="
echo "BIOS PXE → pxelinux.0"
echo "UEFI PXE → grub/bootx64.efi"
echo "ISO + Syslinux + GRUB stored in: $DOWNLOAD_DIR"

