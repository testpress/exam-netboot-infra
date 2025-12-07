#!/usr/bin/env bash
# setup-pxe-ubuntu24.sh
# Single-script PXE server setup for Ubuntu 24.04 Desktop (no kiosk customization).
# Installs Apache, dnsmasq, NFS, syslinux, grub/shim; downloads ISO to /opt/ubuntu.
#
# Usage: sudo ./setup-pxe-ubuntu24.sh
set -euo pipefail

### CONFIGURABLE VARIABLES - modify if needed ###
SERVER_IP="192.168.1.160"            # static IP assigned to this PXE server
NET_IF="enp0s31f6"                   # network interface to bind dnsmasq to (run `ip a` to check)
NET_RANGE="192.168.1.0/24"           # network range for NFS exports + notes
DHCP_START="192.168.1.170"
DHCP_END="192.168.1.200"
ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso"
ISO_DIR="/opt/ubuntu"
ISO_FILE="${ISO_DIR}/ubuntu-24.04.3-desktop-amd64.iso"
WWW_ROOT="/var/www/html/desktop"
WWW_U2404="${WWW_ROOT}/u2404"
TFTP_ROOT="/var/lib/tftpboot"
TFTP_BIOS="${TFTP_ROOT}/bios"
TFTP_GRUB="${TFTP_ROOT}/grub"
TFTP_BOOT="${TFTP_ROOT}/boot"

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root: sudo $0"
  exit 1
fi

echo "=== PXE Setup started ==="
echo "Server IP: ${SERVER_IP}"
echo "Interface: ${NET_IF}"
echo

# 1) Apt update + install packages
echo "-> Installing packages (apache2, nfs-kernel-server, dnsmasq, syslinux, grub, shim)..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 \
  nfs-kernel-server \
  dnsmasq \
  syslinux-common \
  syslinux \
  pxelinux \
  squashfs-tools \
  grub-efi-amd64-signed \
  shim-signed \
  wget \
  unzip

# 2) Create directories
echo "-> Creating directories..."
mkdir -p "${ISO_DIR}"
mkdir -p "${WWW_U2404}"
mkdir -p "${TFTP_BIOS}" "${TFTP_GRUB}" "${TFTP_BOOT}" "${TFTP_ROOT}/boot/casper"

# 3) Download ISO if not present or checksum differs
if [ ! -f "${ISO_FILE}" ]; then
  echo "-> Downloading Ubuntu ISO to ${ISO_FILE}..."
  wget -c "${ISO_URL}" -O "${ISO_FILE}"
else
  echo "-> ISO already exists at ${ISO_FILE}, skipping download."
fi

# 4) Mount ISO, copy contents to web root (idempotent)
MOUNT_POINT="/mnt/iso_ubuntu2404"
mkdir -p "${MOUNT_POINT}"
echo "-> Mounting ISO..."
umount "${MOUNT_POINT}" >/dev/null 2>&1 || true
mount -o loop "${ISO_FILE}" "${MOUNT_POINT}"

echo "-> Copying ISO contents to ${WWW_U2404} (rsync for idempotency)..."
rsync -aH --delete "${MOUNT_POINT}/" "${WWW_U2404}/"

# Ensure casper exists
if [ ! -d "${WWW_U2404}/casper" ]; then
  echo "ERROR: casper directory not found in ISO contents at ${WWW_U2404}/casper"
  umount "${MOUNT_POINT}" || true
  exit 2
fi

echo "-> Unmounting ISO..."
umount "${MOUNT_POINT}"

# 5) Configure NFS export
EXPORT_LINE="${WWW_ROOT} ${NET_RANGE}(ro,sync,no_subtree_check,no_root_squash)"
if ! grep -qsF "${WWW_ROOT}" /etc/exports; then
  echo "-> Configuring NFS exports..."
  echo "${WWW_ROOT} ${NET_RANGE}(ro,sync,no_subtree_check,no_root_squash)" >> /etc/exports
else
  echo "-> NFS export already configured in /etc/exports"
fi

exportfs -ra
systemctl enable --now nfs-kernel-server

# 6) Configure dnsmasq for DHCP/TFTP/PXE
DNSMASQ_CONF="/etc/dnsmasq.d/pxe.conf"
echo "-> Writing dnsmasq configuration to ${DNSMASQ_CONF} ..."
cat > "${DNSMASQ_CONF}" <<EOF
interface=${NET_IF}
bind-interfaces

# PXE DHCP range
dhcp-range=${DHCP_START},${DHCP_END},12h

# PXE boot files
dhcp-match=set:efi64,option:client-arch,7
# UEFI clients get grub boot via signed shim
dhcp-boot=tag:efi64,grub/bootx64.efi
# BIOS clients use pxelinux
dhcp-boot=/bios/pxelinux.0

# TFTP root
enable-tftp
tftp-root=${TFTP_ROOT}

# Gateway + DNS (replace if you want other)
dhcp-option=3,${SERVER_IP}
dhcp-option=6,${SERVER_IP}

# Optional: block all websites by resolving everything to nowhere (comment out if undesired)
# address=/#/0.0.0.0

# Logging
log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF

# Restart dnsmasq
systemctl enable --now dnsmasq

# 7) Populate TFTP: copy BIOS PXELINUX files (pxelinux.0, ldlinux.c32, menu.c32, vesamenu.c32)
echo "-> Populating TFTP BIOS files (pxelinux + modules)..."
# Find pxelinux.0 and syslinux modules
PXELINUX_SRC="$(find /usr/lib -type f -name pxelinux.0 | head -n1 || true)"
if [ -z "${PXELINUX_SRC}" ]; then
  # fallback path
  PXELINUX_SRC="/usr/lib/syslinux/pxelinux.0"
fi
if [ -f "${PXELINUX_SRC}" ]; then
  cp -v "${PXELINUX_SRC}" "${TFTP_BIOS}/"
else
  echo "WARNING: pxelinux.0 not found; please install syslinux/pxelinux package."
fi

# copy common modules (ldlinux.c32, menu.c32, vesamenu.c32, libutil.c32) from known locations
SYS_MODULE_DIRS=( "/usr/lib/syslinux/modules/bios" "/usr/lib/syslinux/modules" "/usr/lib/PXELINUX" "/usr/lib/syslinux" )
for mod in ldlinux.c32 menu.c32 vesamenu.c32 libutil.c32; do
  found=""
  for d in "${SYS_MODULE_DIRS[@]}"; do
    if [ -f "${d}/${mod}" ]; then
      cp -v "${d}/${mod}" "${TFTP_BIOS}/" && found=1 && break
    fi
  done
  if [ -z "${found}" ]; then
    echo "WARNING: module ${mod} not found in expected syslinux dirs."
  fi
done

# symlink boot folder for BIOS pxelinux kernel path
mkdir -p "${TFTP_BIOS}/pxelinux.cfg"
ln -sfn "${TFTP_BOOT}" "${TFTP_BIOS}/boot" || true

# 8) Copy kernel & initrd to TFTP boot folder (from web copy)
echo "-> Copying kernel and initrd to ${TFTP_BOOT}/casper ..."
# Common names: vmlinuz, initrd, initrd.lz, initrd.gz
KERNEL_SRC=""
INITRD_SRC=""
for candidate in vmlinuz linux/vmlinuz; do
  if [ -f "${WWW_U2404}/casper/${candidate}" ]; then
    KERNEL_SRC="${WWW_U2404}/casper/${candidate}"
    break
  fi
done
# fallback to plain name
if [ -z "${KERNEL_SRC}" ] && [ -f "${WWW_U2404}/casper/vmlinuz" ]; then
  KERNEL_SRC="${WWW_U2404}/casper/vmlinuz"
fi

for candidate in initrd initrd.lz initrd.gz initrd.img initrd.lz; do
  if [ -f "${WWW_U2404}/casper/${candidate}" ]; then
    INITRD_SRC="${WWW_U2404}/casper/${candidate}"
    break
  fi
done

if [ -n "${KERNEL_SRC}" ]; then
  cp -v "${KERNEL_SRC}" "${TFTP_BOOT}/casper/vmlinuz"
else
  echo "ERROR: kernel not found in ${WWW_U2404}/casper. Aborting."
  exit 3
fi

if [ -n "${INITRD_SRC}" ]; then
  cp -v "${INITRD_SRC}" "${TFTP_BOOT}/casper/initrd"
else
  echo "ERROR: initrd not found in ${WWW_U2404}/casper. Aborting."
  exit 4
fi

# 9) Install/copy shim + grubnetx64 for UEFI clients
echo "-> Preparing UEFI boot files (shim + grub)..."
# Find shim and grub signed efi files
SHIM_SRC="$(find /usr -type f -name 'shimx64.efi.signed' -o -name 'shimx64.efi' 2>/dev/null | head -n1 || true)"
GRUB_NET_SRC="$(find /usr -type f -name 'grubnetx64.efi.signed' -o -name 'grubnetx64.efi' -o -name 'grubx64.efi' 2>/dev/null | head -n1 || true)"

# If not found in those names try standard paths
if [ -z "${SHIM_SRC}" ] && [ -f "/usr/lib/shim/shimx64.efi.signed" ]; then
  SHIM_SRC="/usr/lib/shim/shimx64.efi.signed"
fi
if [ -z "${GRUB_NET_SRC}" ] && [ -f "/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed" ]; then
  GRUB_NET_SRC="/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed"
fi

# Copy to tftp grub folder
if [ -n "${SHIM_SRC}" ]; then
  cp -v "${SHIM_SRC}" "${TFTP_GRUB}/bootx64.efi"
else
  echo "WARNING: shim not found. UEFI secure-boot clients may not boot. Please install shim-signed."
fi

if [ -n "${GRUB_NET_SRC}" ]; then
  # we will place grubnetx64.efi as grubx64.efi alongside bootx64
  cp -v "${GRUB_NET_SRC}" "${TFTP_ROOT}/grubx64.efi" || true
else
  echo "WARNING: grubnetx64.efi not found in system. UEFI network boot entry may fail."
fi

# Copy grub cfg and font from ISO -> TFTP (if present in web copy)
if [ -f "${WWW_U2404}/boot/grub/grub.cfg" ]; then
  cp -v "${WWW_U2404}/boot/grub/grub.cfg" "${TFTP_GRUB}/"
fi
if [ -f "${WWW_U2404}/boot/grub/font.pf2" ]; then
  cp -v "${WWW_U2404}/boot/grub/font.pf2" "${TFTP_GRUB}/"
fi

# 10) Create PXELINUX config for BIOS clients
echo "-> Writing PXELINUX configuration..."
PXE_CFG="${TFTP_BIOS}/pxelinux.cfg/default"
cat > "${PXE_CFG}" <<EOF
DEFAULT menu.c32
MENU TITLE ULTIMATE PXE SERVER - By Script - Ver 1.0
PROMPT 0
TIMEOUT 0
MENU COLOR TABMSG  37;40  #ffffffff #00000000
MENU COLOR TITLE   37;40  #ffffffff #00000000
MENU COLOR SEL      7     #ffffffff #00000000
MENU COLOR UNSEL    37;40 #ffffffff #00000000
MENU COLOR BORDER   37;40 #ffffffff #00000000

LABEL Ubuntu Desktop 24.04
  kernel /boot/casper/vmlinuz
  append nfsroot=${SERVER_IP}:${WWW_U2404} netboot=nfs ip=dhcp boot=casper initrd=/boot/casper/initrd
EOF

# 11) Create GRUB config for UEFI clients (fallback menu if not provided)
echo "-> Writing GRUB configuration for UEFI clients..."
GRUB_CFG="${TFTP_GRUB}/grub.cfg"
cat > "${GRUB_CFG}" <<EOF
if loadfont /grub/font.pf2 ; then
  set gfxmode=auto
  insmod efi_gop
  insmod efi_uga
  insmod gfxterm
  terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
set timeout=5

menuentry "Ubuntu Desktop 24.04" {
  set gfxpayload=keep
  linux /boot/casper/vmlinuz ip=dhcp nfsroot=${SERVER_IP}:${WWW_U2404} netboot=nfs boot=casper
  initrd /boot/casper/initrd
}
EOF

# 12) Ensure permissions
chown -R www-data:www-data "${WWW_ROOT}" || true
chmod -R 755 "${TFTP_ROOT}" "${WWW_ROOT}"

# 13) Restart apache2 and dnsmasq to pick up changes
echo "-> Restarting services..."
systemctl enable --now apache2
systemctl restart dnsmasq
systemctl restart nfs-kernel-server || true

echo
echo "=== Setup complete ==="
echo "PXE server files:"
echo " - Web (HTTP) root: ${WWW_U2404}"
echo " - NFS export: ${WWW_ROOT} -> ${NET_RANGE} (read-only)"
echo " - TFTP root: ${TFTP_ROOT}"
echo
echo "Validation checklist:"
echo " 1) Ensure ${SERVER_IP} is configured on interface ${NET_IF} and is reachable."
echo "    - ip addr show ${NET_IF}"
echo " 2) Check Apache serving ISO contents: http://${SERVER_IP}/desktop/u2404/"
echo "    - curl -I http://${SERVER_IP}/desktop/u2404/"
echo " 3) Check dnsmasq status and logs:"
echo "    - systemctl status dnsmasq"
echo "    - tail -n 80 /var/log/dnsmasq.log"
echo " 4) Check NFS export:"
echo "    - showmount -e ${SERVER_IP}"
echo " 5) Check TFTP files (pxelinux, vmlinuz, initrd):"
echo "    - ls -l ${TFTP_BIOS} ${TFTP_BOOT}/casper ${TFTP_GRUB}"
echo
echo "If clients fail to PXE boot, common fixes:"
echo " - Verify DNSMASQ interface name ${NET_IF} and that no other DHCP server is running on the network."
echo " - Ensure firewall on the server allows UDP ports 67,68,69 and NFS ports (111,2049,20048)."
echo " - For UEFI Secure Boot clients: ensure shim-signed and grub signed files exist (see ${TFTP_GRUB})."
echo
echo "Logs: /var/log/dnsmasq.log, /var/log/syslog (dnsmasq messages), systemctl status outputs."
echo
echo "Script finished."

