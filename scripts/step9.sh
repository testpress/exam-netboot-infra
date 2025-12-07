#!/usr/bin/env bash
set -e

SERVER_IP="192.168.1.160"

PXE_BIOS_CFG="/var/lib/tftpboot/bios/pxelinux.cfg/default"
PXE_GRUB_CFG="/var/lib/tftpboot/grub/grub.cfg"

echo "-> Creating PXELINUX configuration (BIOS)..."
sudo mkdir -p /var/lib/tftpboot/bios/pxelinux.cfg

sudo tee "${PXE_BIOS_CFG}" > /dev/null <<EOF
DEFAULT menu.c32

MENU TITLE ULTIMATE PXE SERVER - By Griffon - Ver 2.1

PROMPT 0
TIMEOUT 0

MENU COLOR TABMSG  37;40  #ffffffff #00000000
MENU COLOR TITLE   37;40  #ffffffff #00000000
MENU COLOR SEL      7     #ffffffff #00000000
MENU COLOR UNSEL    37;40 #ffffffff #00000000
MENU COLOR BORDER   37;40 #ffffffff #00000000

LABEL Ubuntu Desktop 24.04
    kernel /boot/casper/vmlinuz
    append nfsroot=${SERVER_IP}:/var/www/html/desktop/u2404 netboot=nfs ip=dhcp boot=casper initrd=/boot/casper/initrd
EOF


echo "-> Creating GRUB configuration (UEFI)..."
sudo mkdir -p /var/lib/tftpboot/grub

sudo tee "${PXE_GRUB_CFG}" > /dev/null <<EOF
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


echo "-> Restarting PXE services..."
sudo systemctl restart apache2 || true
sudo systemctl restart nfs-kernel-server || true
sudo systemctl restart dnsmasq || true

echo "-> Checking service health..."
sudo systemctl status apache2 --no-pager
sudo systemctl status nfs-kernel-server --no-pager
sudo systemctl status dnsmasq --no-pager

echo "-> PXELINUX + GRUB configuration complete."

