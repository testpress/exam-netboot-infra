#!/bin/bash
set -euo pipefail

# configure-pxe-setup.sh
# Creates TFTP/HTTP/NFS layout, downloads ISO from your cloud bucket (ISO_URL),
# extracts it into webroot, configures /etc/exports and /etc/dnsmasq.d/pxe.conf,
# creates a minimal nginx site to serve webroot and restarts services.

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo $0"
  exit 1
fi

### CONFIG - change as needed ###
SERVER_IP="${SERVER_IP:-192.168.1.160}"
NET_RANGE="${NET_RANGE:-192.168.1.0/24}"
IFACE="${IFACE:-enp0s31f6}"
ISO_URL="${ISO_URL:-}"            # e.g. "https://your-bucket.example.com/Porteus-Kiosk.iso"
ISO_LOCAL="${ISO_LOCAL:-/opt/isos/pxe.iso}"
WEBROOT_BASE="${WEBROOT_BASE:-/var/www/pxe}"
WEBROOT="${WEBROOT:-$WEBROOT_BASE/desktop/u2404}"
TFTP_ROOT="${TFTP_ROOT:-/var/lib/tftpboot}"
MOUNT_POINT="${MOUNT_POINT:-/media/iso_pxe_mount}"
DNSMASQ_CONF="/etc/dnsmasq.d/pxe.conf"
NGINX_SITE="/etc/nginx/sites-available/pxe"

die(){ echo "[FATAL] $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
ok(){ echo "[✔] $*"; }

# Ensure required commands exist
for cmd in nginx dnsmasq exportfs mount umount wget; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Required command not found: $cmd. Install dependencies first."
  fi
done

info "Creating directories..."
mkdir -p "$TFTP_ROOT"/{bios,boot,grub}
mkdir -p "$WEBROOT"
mkdir -p "$MOUNT_POINT"
mkdir -p "$(dirname "$ISO_LOCAL")"

# Download ISO if ISO_URL provided
if [ -n "$ISO_URL" ]; then
  info "Downloading ISO from: $ISO_URL"
  # download with resume and follow redirects
  if ! wget -c -O "$ISO_LOCAL" "$ISO_URL"; then
    die "Failed to download ISO from $ISO_URL"
  fi
  ok "ISO downloaded to $ISO_LOCAL"
else
  if [ ! -f "$ISO_LOCAL" ]; then
    echo "[FATAL] No ISO_URL provided and $ISO_LOCAL not found."
    echo "Place ISO at $ISO_LOCAL or set ISO_URL env var."
    exit 1
  fi
fi

# Basic sanity of ISO file size
if [ ! -s "$ISO_LOCAL" ]; then
  die "ISO file is empty or missing: $ISO_LOCAL"
fi

info "Mounting ISO and extracting to webroot..."
if mountpoint -q "$MOUNT_POINT"; then
  umount "$MOUNT_POINT" || true
fi

if ! mount -o loop "$ISO_LOCAL" "$MOUNT_POINT"; then
  die "Failed to mount ISO $ISO_LOCAL at $MOUNT_POINT"
fi

# Copy contents
if ! cp -a "$MOUNT_POINT"/. "$WEBROOT"/; then
  umount "$MOUNT_POINT" || true
  die "Failed copying ISO contents to $WEBROOT"
fi

# ensure .disk if exists is copied
if [ -e "$MOUNT_POINT/.disk" ]; then
  cp -a "$MOUNT_POINT/.disk" "$WEBROOT"/ || true
fi

umount "$MOUNT_POINT"
ok "ISO extracted to $WEBROOT"

### Configure NFS exports
info "Configuring NFS exports..."
cat > /etc/exports <<EOF
$WEBROOT_BASE $NET_RANGE(ro,no_subtree_check,async)
EOF

if ! exportfs -ra; then
  die "exportfs -ra failed"
fi
ok "NFS exports configured: $WEBROOT_BASE -> $NET_RANGE (ro)"

### Configure dnsmasq
info "Writing dnsmasq config to $DNSMASQ_CONF"
cat > "$DNSMASQ_CONF" <<EOF
interface=$IFACE
bind-interfaces

# DHCP range
dhcp-range=192.168.1.170,192.168.1.200,12h

# Boot files for BIOS and UEFI
dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,grub/bootx64.efi
dhcp-boot=/bios/pxelinux.0

enable-tftp
tftp-root=$TFTP_ROOT

dhcp-option=3,${SERVER_IP}
dhcp-option=6,${SERVER_IP}

log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF
ok "dnsmasq config written"

### Configure nginx site
info "Creating nginx site for $WEBROOT_BASE"
cat > "$NGINX_SITE" <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/pxe;
    autoindex on;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/pxe
if [ -f /etc/nginx/sites-enabled/default ]; then rm -f /etc/nginx/sites-enabled/default; fi

chown -R www-data:www-data "$WEBROOT_BASE" || true
chmod -R 755 "$WEBROOT_BASE" || true
ok "nginx site enabled"

### Restart services
info "Restarting services..."
systemctl restart nginx || die "nginx failed to restart"
systemctl restart nfs-kernel-server || die "nfs-kernel-server failed to restart"
systemctl restart dnsmasq || die "dnsmasq failed to restart"
ok "Services restarted"

echo "=========================================="
echo "[✔] configure-pxe-setup complete"
echo "    WEBROOT: $WEBROOT"
echo "    TFTP:    $TFTP_ROOT"
echo "    ISO:     $ISO_LOCAL"
echo "=========================================="
exit 0

