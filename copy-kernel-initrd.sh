#!/bin/bash
set -euo pipefail

TFTP_BOOT="/var/lib/tftpboot/boot/casper"
WEBROOT="/var/www/html/desktop/u2404"
VMLINZ_PATH="$WEBROOT/casper/vmlinuz"
INITRD_PATH="$WEBROOT/casper/initrd"
TFTP_VMLINZ="$TFTP_BOOT/vmlinuz"
TFTP_INITRD="$TFTP_BOOT/initrd"

echo "=== copy-kernel-initrd.sh ==="

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo ./copy-kernel-initrd.sh"
  exit 1
fi

# Validate source files exist
if [ ! -f "$VMLINZ_PATH" ] && [ ! -f "$WEBROOT/casper/vmlinuz.efi" ]; then
  echo "[FATAL] Kernel not found under $WEBROOT/casper. Ensure ISO was extracted."
  exit 1
fi

if [ ! -f "$INITRD_PATH" ]; then
  # sometimes initrd name is initrd.lz or initrd.gz
  alt="$(ls $WEBROOT/casper | grep -E 'initrd|initramfs' | head -n1 || true)"
  if [ -n "$alt" ]; then
    INITRD_PATH="$WEBROOT/casper/$alt"
  else
    echo "[FATAL] initrd not found under $WEBROOT/casper. Ensure ISO was extracted."
    exit 1
  fi
fi

mkdir -p "$TFTP_BOOT"

echo "[*] Copying kernel and initrd to tftpboot..."
cp -v "$VMLINZ_PATH" "$TFTP_VMLINZ"
cp -v "$INITRD_PATH" "$TFTP_INITRD"

chmod 644 "$TFTP_VMLINZ" "$TFTP_INITRD"

echo "[✔] Kernel and initrd copied to $TFTP_BOOT"
echo "    - $TFTP_VMLINZ"
echo "    - $TFTP_INITRD"

exit 0

