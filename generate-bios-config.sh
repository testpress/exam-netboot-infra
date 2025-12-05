#!/bin/bash
set -euo pipefail

TFTP_BIOS_DIR="/var/lib/tftpboot/bios"
TFTP_BOOT_DIR="/var/lib/tftpboot/boot/casper"
SERVER_IP="192.168.1.160"
CFG_FILE="$TFTP_BIOS_DIR/pxelinux.cfg/default"

echo "=== generate-bios-config.sh ==="

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo ./generate-bios-config.sh"
  exit 1
fi

# Ensure pxelinux exists
if [ ! -f "$TFTP_BIOS_DIR/pxelinux.0" ]; then
  echo "[FATAL] pxelinux.0 not found in $TFTP_BIOS_DIR. Run install-bootloaders.sh first."
  exit 1
fi

# Ensure kernel/initrd exist
if [ ! -f "$TFTP_BOOT_DIR/vmlinuz" ]; then
  echo "[FATAL] Kernel vmlinuz not found in $TFTP_BOOT_DIR. Run copy-kernel-initrd.sh first."
  exit 1
fi

if [ ! -f "$TFTP_BOOT_DIR/initrd" ]; then
  echo "[FATAL] initrd not found in $TFTP_BOOT_DIR. Run copy-kernel-initrd.sh first."
  exit 1
fi

mkdir -p "$(dirname "$CFG_FILE")"

cat > "$CFG_FILE" <<EOF
DEFAULT menu.c32
MENU TITLE PXE BIOS Boot Menu
PROMPT 0
TIMEOUT 0

LABEL Ubuntu Desktop 24.04
  KERNEL /boot/casper/vmlinuz
  APPEND nfsroot=$SERVER_IP:/var/www/html/desktop/u2404 netboot=nfs ip=dhcp boot=casper initrd=/boot/casper/initrd
EOF

chmod 644 "$CFG_FILE"
echo "[✔] BIOS PXELinux config written to $CFG_FILE"

exit 0

