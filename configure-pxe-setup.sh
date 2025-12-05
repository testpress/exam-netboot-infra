#!/bin/bash
set -e

### CONFIG ###
SERVER_IP="192.168.1.160"
NET_RANGE="192.168.1.0/24"
IFACE="enp0s31f6"
ISO_PATH="ubuntu-24.04.3-desktop-amd64.iso"
WEBROOT="/var/www/html/desktop/u2404"

echo "=== PXE Server Configuration ==="

### 1️⃣ CHECK PREREQUISITES ###
echo "[*] Validating environment…"

if ! command -v apache2 >/dev/null 2>&1; then
    echo "[FATAL] Apache2 is not installed. Cannot proceed."
    exit 1
fi

if ! command -v dnsmasq >/dev/null 2>&1; then
    echo "[FATAL] dnsmasq is not installed. Cannot proceed."
    exit 1
fi

if ! command -v exportfs >/dev/null 2>&1; then
    echo "[FATAL] NFS server tools are missing. Cannot proceed."
    exit 1
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "[FATAL] ISO file not found: $ISO_PATH"
    echo "        Place the Ubuntu ISO in this directory and retry."
    exit 1
fi

if ! ip addr show "$IFACE" >/dev/null 2>&1; then
    echo "[FATAL] Network interface '$IFACE' does not exist."
    echo "        Run: ip a  to find correct interface name."
    exit 1
fi

echo "[✔] Environment validated."


### 2️⃣ CREATE FOLDERS ###
echo "[*] Creating directory structure…"

mkdir -p /var/lib/tftpboot/{bios,boot,grub}
mkdir -p "$WEBROOT"

echo "[✔] Directory structure ready."


### 3️⃣ COPY ISO CONTENTS ###
echo "[*] Extracting ISO into webroot…"

mount -o loop "$ISO_PATH" /media || {
    echo "[FATAL] Failed to mount ISO."
    exit 1
}

cp -rf /media/* "$WEBROOT" || {
    echo "[FATAL] Failed copying ISO contents."
    umount /media
    exit 1
}

cp -rf /media/.disk "$WEBROOT"
umount /media

echo "[✔] ISO extracted successfully."


### 4️⃣ CONFIGURE NFS ###
echo "[*] Configuring NFS export…"

/bin/cat <<EOF >/etc/exports
/var/www/html/desktop $NET_RANGE(ro)
EOF

if ! exportfs -ra; then
    echo "[FATAL] Failed to apply NFS export."
    exit 1
fi

echo "[✔] NFS export configured."


### 5️⃣ CONFIGURE DNSMASQ ###
echo "[*] Writing dnsmasq PXE configuration…"

/bin/cat <<EOF >/etc/dnsmasq.d/pxe.conf
interface=$IFACE
bind-interfaces

dhcp-range=192.168.1.170,192.168.1.200,12h

dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,grub/bootx64.efi
dhcp-boot=/bios/pxelinux.0

enable-tftp
tftp-root=/var/lib/tftpboot

dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1

log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF

echo "[✔] dnsmasq config ready."


### 6️⃣ RESTART SERVICES ###
echo "[*] Restarting services…"

systemctl restart apache2 || { echo "[FATAL] Apache failed."; exit 1; }
systemctl restart nfs-kernel-server || { echo "[FATAL] NFS failed."; exit 1; }
systemctl restart dnsmasq || { echo "[FATAL] dnsmasq failed."; exit 1; }

echo "========================================="
echo "[✔] PXE server configuration completed."
echo "    Webroot: $WEBROOT"
echo "    TFTP:    /var/lib/tftpboot"
echo "    NFS:     /etc/exports"
echo "========================================="

