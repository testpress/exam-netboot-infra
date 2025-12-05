#!/bin/bash
set -euo pipefail

# install-dependencies.sh
# Installs necessary packages for PXE server (nginx, dnsmasq, nfs, syslinux/grub, squashfs-tools)

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo $0"
  exit 1
fi

PACKAGES=(
  nginx
  dnsmasq
  nfs-kernel-server
  wget
  unzip
  squashfs-tools
  syslinux
  pxelinux
  syslinux-common
  grub-efi-amd64-signed
  shim-signed
)

echo "=== install-dependencies.sh ==="
echo "[*] Updating apt lists..."
apt-get update -y || { echo "[FATAL] apt-get update failed"; exit 1; }

echo "[*] Installing packages..."
for pkg in "${PACKAGES[@]}"; do
  echo " -> $pkg"
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; then
    echo "[FATAL] Failed to install package: $pkg"
    exit 1
  fi
done

echo "[✔] All dependencies installed."
exit 0

