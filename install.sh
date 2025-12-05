#!/bin/bash

set -e

PACKAGES=(
    apache2
    nfs-kernel-server
    dnsmasq
    unzip
    wget
    squashfs-tools
)

echo "=== PXE Server Dependency Installer ==="
echo "[*] Updating package lists…"

if ! apt update -y; then
    echo "[ERROR] Failed to update package lists. Cannot proceed."
    exit 1
fi

echo "[*] Installing required packages…"

for pkg in "${PACKAGES[@]}"; do
    echo "→ Installing: $pkg"
    if ! apt install -y "$pkg"; then
        echo "[FATAL] Failed to install package: $pkg"
        echo "        Installation cannot continue. Fix the issue and retry."
        exit 1
    fi
done

echo "========================================="
echo "[✔] All required packages installed successfully."
echo "    Installed:"
for pkg in "${PACKAGES[@]}"; do
    echo "    - $pkg"
done
echo "========================================="

