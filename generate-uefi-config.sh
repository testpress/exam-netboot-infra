#!/bin/bash
set -euo pipefail

TFTP_GRUB_DIR="/var/lib/tftpboot/grub"
TFTP_BOOT_DIR="/var/lib/tftpboot/boot/casper"
TFTP_ROOT="/var/lib/tftpboot"
SERVER_IP="192.168.1.160"
CFG_FILE="$TFTP_GRUB_DIR/grub.cfg"

echo "=== generate-uefi-config.sh ==="

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo ./generate-uefi-config.sh"
  exit 1
fi

# Validate GRUB EFI binary exists
if [ ! -f "$TFTP_ROOT/grubx64.efi" ] && [ ! -f "$TFTP_GRUB_DIR/bootx64.efi" ]; then
  echo "[FATAL] GRUB or shim EFI binaries not found in $TFTP_ROOT or $TFTP_GRUB_DIR. Run install-bootloaders.sh first."
  exit 1
fi

# Validate kernel/initrd exist
if [ ! -f "$TFTP_BOOT_DIR/vmlinuz" ]; then
  echo "[FATAL] Kernel vmlinuz not found in $TFTP_BOOT_DIR. Run copy-kernel-initrd.sh first."
  exit 1
fi

if [ ! -f "$TFTP_BOOT_DIR/initrd" ]; then
  echo "[FATAL] initrd not found in $TFTP_BOOT_DIR. Run copy-kernel-initrd.sh first."
  exit 1
fi

mkdir -p "$TFTP_GRUB_DIR"

cat > "$CFG_FILE" <<EOF
if loadfont /grub/font.pf2 ; then
  set gfxmode=auto
  insmod efi_gop
  insmod efi_uga
  insmod gfxterm
  terminal_output gfxterm
fi

set timeout=5
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Ubuntu Desktop 24.04 (Netboot)" {
  set gfxpayload=keep
  linux /boot/casper/vmlinuz ip=dhcp nfsroot=$SERVER_IP:/var/www/html/desktop/u2404/ netboot=nfs boot=casper
  initrd /boot/casper/initrd
}
EOF

chmod 644 "$CFG_FILE"
echo "[✔] UEFI GRUB config written to $CFG_FILE"

exit 0

