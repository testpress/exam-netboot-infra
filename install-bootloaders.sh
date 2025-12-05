#!/bin/bash
set -euo pipefail

# install-bootloaders.sh
# Installs/ensures PXELINUX and GRUB EFI bootloaders are present and copies them into tftp root.

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo $0"
  exit 1
fi

TFTP_ROOT="${TFTP_ROOT:-/var/lib/tftpboot}"
BIOS_DIR="$TFTP_ROOT/bios"
GRUB_DIR="$TFTP_ROOT/grub"

die(){ echo "[FATAL] $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
ok(){ echo "[✔] $*"; }

# Ensure packages are installed - apt will be idempotent if already present
info "Installing packages for bootloaders..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
for pkg in syslinux pxelinux syslinux-common grub-efi-amd64-signed shim-signed; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    info "Installing $pkg..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; then
      die "Failed to install $pkg"
    fi
  else
    info "Package $pkg already installed"
  fi
done

info "Creating tftp directories..."
mkdir -p "$BIOS_DIR" "$GRUB_DIR" "$TFTP_ROOT/boot/casper"

# Copy pxelinux.0
info "Locating pxelinux.0..."
PXELINUX_SRC="$(dpkg -L syslinux 2>/dev/null | grep -E '/pxelinux.0$' | head -n1 || true)"
if [ -z "$PXELINUX_SRC" ]; then
  # Try common fallback
  PXELINUX_SRC="/usr/lib/PXELINUX/pxelinux.0"
fi

if [ ! -f "$PXELINUX_SRC" ]; then
  die "pxelinux.0 not found. Ensure syslinux/pxelinux installed."
fi

cp -v "$PXELINUX_SRC" "$BIOS_DIR/pxelinux.0"

# Copy common syslinux modules
for mod in ldlinux.c32 menu.c32 vesamenu.c32 libutil.c32; do
  src="$(dpkg -L syslinux 2>/dev/null | grep "/$mod$" | head -n1 || true)"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cp -v "$src" "$BIOS_DIR/" || true
  else
    echo "[WARN] $mod not found via dpkg -L; skipping"
  fi
done

# Copy GRUB EFI and shim
GRUB_EFI_SRC="$(dpkg -L grub-efi-amd64-signed 2>/dev/null | grep -E 'grubnetx64.*efi' | head -n1 || true)"
SHIM_SRC="$(dpkg -L shim-signed 2>/dev/null | grep -E 'shimx64.*efi' | head -n1 || true)"

if [ -z "$GRUB_EFI_SRC" ] || [ ! -f "$GRUB_EFI_SRC" ]; then
  die "grubnetx64 EFI binary not found. Ensure grub-efi-amd64-signed installed."
fi

if [ -z "$SHIM_SRC" ] || [ ! -f "$SHIM_SRC" ]; then
  die "shimx64 EFI binary not found. Ensure shim-signed installed."
fi

cp -v "$GRUB_EFI_SRC" "$TFTP_ROOT/grubx64.efi"
mkdir -p "$GRUB_DIR"
cp -v "$SHIM_SRC" "$GRUB_DIR/bootx64.efi"

chmod 644 "$BIOS_DIR/"* || true
chmod 644 "$TFTP_ROOT/"* || true
chmod 644 "$GRUB_DIR/"* || true

ok "Bootloader binaries copied to $TFTP_ROOT"
exit 0

