#!/bin/bash
set -euo pipefail

# copy-kernel-initrd.sh
# Copies kernel + initrd from the extracted ISO webroot into TFTP boot area (/var/lib/tftpboot/boot/casper).
# Accepts optional overrides: WEBROOT (source) and TFTP_BOOT (destination)

if [ "$EUID" -ne 0 ]; then
  echo "[FATAL] Run as root: sudo $0"
  exit 1
fi

WEBROOT="${WEBROOT:-/var/www/pxe/desktop/u2404}"
TFTP_BOOT="${TFTP_BOOT:-/var/lib/tftpboot/boot/casper}"

die(){ echo "[FATAL] $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
ok(){ echo "[✔] $*"; }

info "Locating kernel and initrd inside $WEBROOT..."

# Prefer common names; try multiple fallbacks
KERNEL_CANDIDATES=("$WEBROOT/casper/vmlinuz" "$WEBROOT/boot/vmlinuz" "$WEBROOT/vmlinuz" )
INITRD_CANDIDATES=("$WEBROOT/casper/initrd" "$WEBROOT/casper/initrd.lz" "$WEBROOT/casper/initrd.xz" "$WEBROOT/boot/initrd" "$WEBROOT/initrd")

KERNEL=""
INITRD=""

for f in "${KERNEL_CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    KERNEL="$f"
    break
  fi
done

for f in "${INITRD_CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    INITRD="$f"
    break
  fi
done

if [ -z "$KERNEL" ]; then
  die "Kernel not found in webroot. Checked: ${KERNEL_CANDIDATES[*]}"
fi

if [ -z "$INITRD" ]; then
  die "Initrd not found in webroot. Checked: ${INITRD_CANDIDATES[*]}"
fi

info "Kernel found: $KERNEL"
info "Initrd found: $INITRD"

mkdir -p "$TFTP_BOOT"

TFTP_KERNEL="$TFTP_BOOT/$(basename "$KERNEL")"
TFTP_INITRD="$TFTP_BOOT/$(basename "$INITRD")"

info "Copying kernel -> $TFTP_KERNEL"
cp -v "$KERNEL" "$TFTP_KERNEL"
info "Copying initrd -> $TFTP_INITRD"
cp -v "$INITRD" "$TFTP_INITRD"

chmod 644 "$TFTP_KERNEL" "$TFTP_INITRD" || true

ok "Kernel and initrd copied to $TFTP_BOOT"
exit 0

