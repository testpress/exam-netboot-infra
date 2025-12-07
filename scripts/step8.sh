#!/usr/bin/env bash
set -e

DNSMASQ_CONF="/etc/dnsmasq.d/pxe.conf"
NET_IF="enp0s31f6"
GATEWAY_DNS="192.168.1.1"

echo "-> Writing PXE dnsmasq config to ${DNSMASQ_CONF} ..."

sudo tee "${DNSMASQ_CONF}" > /dev/null <<EOF
# -----------------------------
# INTERFACE + BINDING
# -----------------------------
interface=${NET_IF}
bind-interfaces

# -----------------------------
# DHCP RANGE
# -----------------------------
dhcp-range=192.168.1.170,192.168.1.200,12h

# -----------------------------
# BOOTLOADERS
# -----------------------------

# Detect UEFI 64-bit clients
dhcp-match=set:efi64,option:client-arch,7

# UEFI → shim → GRUB
dhcp-boot=tag:efi64,grub/bootx64.efi

# BIOS → pxelinux  (must be tagged !efi64 to avoid dnsmasq keyword error)
dhcp-boot=tag:!efi64,bios/pxelinux.0

# -----------------------------
# TFTP
# -----------------------------
enable-tftp
tftp-root=/var/lib/tftpboot

# -----------------------------
# NETWORK SETTINGS
# -----------------------------
dhcp-option=3,${GATEWAY_DNS}
dhcp-option=6,${GATEWAY_DNS}

# -----------------------------
# BLOCK INTERNET (remove to allow internet)
# -----------------------------
address=/#/0.0.0.0

# -----------------------------
# LOGGING
# -----------------------------
log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF

echo "-> Restarting dnsmasq..."
sudo systemctl restart dnsmasq

echo "-> dnsmasq configuration applied successfully."

