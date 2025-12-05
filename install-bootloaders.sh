#!/bin/bash
set -euo pipefail

# CONFIG
TFTP_ROOT="/var/lib/tftpboot"
BIOS_DIR="$TFTP_ROOT/bios"
GRUB_DIR="$TFTP_ROOT/grub"
WEBROOT="/var/www/html/desktop/u2404"

echo "=== install-bootloaders.sh ==="

# must be root
if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo ./install-bootloaders.sh"
  exit 1
fi

echo "[*] Installing packages required for bootloaders..."
if ! apt-get update -y; then
  echo "[FATAL] apt-get update failed. Cannot proceed."
  exit 1
fi

PKGS=(syslinux pxelinux syslinux-common grub-efi-amd64-signed shim-signed)
for p in "${PKGS[@]}"; do
  echo " -> Installing $p"
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$p"; then
    echo "[FATAL] Failed to install package: $p. Fix and retry."
    exit 1
  fi
done

echo "[*] Creating tftp directories..."
mkdir -p "$BIOS_DIR" "$GRUB_DIR" "$TFTP_ROOT/boot/casper"

# Copy BIOS PXELINUX files
echo "[*] Locating PXELINUX binaries..."
PXELINUX_SRC="$(dpkg -L syslinux 2>/dev/null | grep -E '/pxelinux.0$' | head -n1 || true)"
if [ -z "$PXELINUX_SRC" ]; then
  # fallback common locations
  PXELINUX_SRC="/usr/lib/PXELINUX/pxelinux.0"
fi

if [ ! -f "$PXELINUX_SRC" ]; then
  echo "[FATAL] pxelinux.0 not found on system. Ensure syslinux/pxelinux is installed."
  exit 1
fi

echo "[*] Copying pxelinux and modules..."
cp -v "$PXELINUX_SRC" "$BIOS_DIR/pxelinux.0"
# copy common modules (ldlinux.c32, menu.c32, vesamenu.c32, libutil.c32) if available
for f in ldlinux.c32 menu.c32 vesamenu.c32 libutil.c32; do
  src="$(dpkg -L syslinux 2>/dev/null | grep "/$f$" | head -n1 || true)"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cp -v "$src" "$BIOS_DIR/"
  else
    echo "[WARN] $f not found; some PXELINUX menus may not work. Install syslinux modules."
  fi
done

# Copy GRUB EFI + shim
GRUB_EFI_SRC="$(dpkg -L grub-efi-amd64-signed 2>/dev/null | grep -E 'grubnetx64.*efi' | head -n1 || true)"
SHIM_SRC="$(dpkg -L shim-signed 2>/dev/null | grep -E 'shimx64.*efi' | head -n1 || true)"

if [ -z "$GRUB_EFI_SRC" ] || [ ! -f "$GRUB_EFI_SRC" ]; then
  echo "[FATAL] grubnetx64 EFI binary not found. Ensure grub-efi-amd64-signed is installed."
  exit 1
fi

if [ -z "$SHIM_SRC" ] || [ ! -f "$SHIM_SRC" ]; then
  echo "[FATAL] shimx64 EFI binary not found. Ensure shim-signed is installed."
  exit 1
fi

echo "[*] Copying GRUB EFI and shim to TFTP..."
cp -v "$GRUB_EFI_SRC" "$TFTP_ROOT/grubx64.efi"
cp -v "$SHIM_SRC" "$GRUB_DIR/bootx64.efi"

# Ensure permissions
chmod 644 "$BIOS_DIR/"* || true
chmod 644 "$TFTP_ROOT/"* || true
chmod 644 "$GRUB_DIR/"* || true

echo "[✔] Bootloader binaries placed:"
echo "    - BIOS: $BIOS_DIR/pxelinux.0"
echo "    - UEFI shim: $GRUB_DIR/bootx64.efi"
echo "    - UEFI grub: $TFTP_ROOT/grubx64.efi"

exit 0

