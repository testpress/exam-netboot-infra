#!/usr/bin/env bash
set -e

NET_RANGE="192.168.1.0/24"
NFS_DIR="/var/www/html/desktop"
EXPORT_LINE="${NFS_DIR} ${NET_RANGE}(ro,sync,no_subtree_check,no_root_squash)"

# Ensure directory exists
mkdir -p "${NFS_DIR}"

echo "-> Configuring NFS export for ${NFS_DIR}..."

# Add export only if it doesn’t already exist
if ! grep -qsF "${NFS_DIR}" /etc/exports; then
    echo "${EXPORT_LINE}" | sudo tee -a /etc/exports > /dev/null
    echo "-> Added NFS export: ${EXPORT_LINE}"
else
    echo "-> NFS export already exists. Skipping."
fi

# Reload exports
sudo exportfs -ra

# Restart NFS service
sudo systemctl restart nfs-kernel-server

echo "-> NFS export applied successfully."

