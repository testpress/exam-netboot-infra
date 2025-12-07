#!/usr/bin/env bash
set -e

SERVER_IP="192.168.1.160"
GRUB_CFG="/var/lib/tftpboot/grub/grub.cfg"

echo "-> Writing GRUB configuration for UEFI PXE clients..."

# Ensure GRUB directory exists
sudo mkdir -p /var/lib/tftpboot/grub

sudo tee "${GRUB_CFG}" > /dev/null <<EOF
if loadfont /grub/font.pf2 ; then
    set gfxmode=auto
    insmod efi_gop
    insmod efi_uga
    insmod gfxterm
    terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
set timeout=5

menuentry "Ubuntu Desktop 24.04" {
    set gfxpayload=keep
    linux /boot/casper/vmlinuz ip=dhcp nfsroot=${SERVER_IP}:/var/www/html/desktop/u2404/ netboot=nfs boot=casper
    initrd /boot/casper/initrd
}
EOF

echo "-> GRUB UEFI configuration written to ${GRUB_CFG}"

echo "-> Restarting PXE related services..."
sudo systemctl restart apache2 || true
sudo systemctl restart nfs-kernel-server || true
sudo systemctl restart dnsmasq || true

echo
echo "-> Checking service status..."
sudo systemctl status apache2 --no-pager || true
sudo systemctl status nfs-kernel-server --no-pager || true
sudo systemctl status dnsmasq --no-pager || true

echo
echo "-> PXE UEFI boot configuration complete."

