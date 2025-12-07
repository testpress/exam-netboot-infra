#!/bin/bash
set -e

### ----------------------------
### CONFIGURATION
### ----------------------------
SERVER_IP="192.168.0.160"
WEBROOT="/var/www/html/desktop/u2404"
TFTPROOT="/tftp"
CASPER="$WEBROOT/casper"

### ----------------------------
### VALIDATION
### ----------------------------

if [[ ! -d "$CASPER" ]]; then
    echo "FATAL: $CASPER does not exist. Verify ISO extraction."
    exit 1
fi

### ----------------------------
### STEP 8.3 – Populate boot folder
### ----------------------------

mkdir -p $TFTPROOT/boot/casper

cp $CASPER/vmlinuz  $TFTPROOT/boot/casper/
cp $CASPER/initrd   $TFTPROOT/boot/casper/

echo "[OK] Boot/casper populated."


### ----------------------------
### STEP 8.4 – Create symbolic link
### ----------------------------

ln -sf $TFTPROOT/boot  $TFTPROOT/bios/boot

echo "[OK] Symlink bios/boot → boot created."


### ----------------------------
### STEP 9.1 – Create pxelinux.cfg
### ----------------------------

mkdir -p $TFTPROOT/bios/pxelinux.cfg

cat <<EOF > $TFTPROOT/bios/pxelinux.cfg/default
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

echo "[OK] pxelinux.cfg/default created."


### ----------------------------
### STEP 9.2 – Create grub.cfg
### ----------------------------

cat <<EOF > $TFTPROOT/grub/grub.cfg
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

echo "[OK] grub.cfg created."


echo ""
echo "-----------------------------------------"
echo "[SUCCESS] PXE bootloader assets deployed."
echo "-----------------------------------------"

