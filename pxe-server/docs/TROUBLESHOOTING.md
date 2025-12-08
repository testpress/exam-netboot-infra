# Troubleshooting Guide

Common issues and solutions for PXE server setup and operation.

## Installation Issues

### Package Installation Fails

**Symptom**: `apt-get install` fails with dependency errors.

**Solutions**:
```bash
# Update package cache
sudo apt-get update

# Fix broken dependencies
sudo apt-get -f install

# Clear apt cache and retry
sudo apt-get clean
sudo apt-get update
sudo ./install.sh --iso /path/to/ubuntu.iso
```

### ISO Not Found

**Symptom**: `ISO not found: /root/ubuntu-24.04.3-desktop-amd64.iso`

**Solutions**:
```bash
# Verify ISO exists and path is correct
ls -la /root/*.iso

# Download Ubuntu Desktop ISO
wget -O /root/ubuntu-24.04.3-desktop-amd64.iso \
  https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso

# Use correct path
sudo ./install.sh --iso /correct/path/to/ubuntu.iso
```

### Insufficient Disk Space

**Symptom**: `Insufficient disk space: XGB available, need 15GB+`

**Solutions**:
```bash
# Check disk space
df -h /

# Clean up old files
sudo apt-get autoremove
sudo apt-get clean
sudo rm -rf /tmp/*

# Remove old kernels
sudo apt-get autoremove --purge
```

---

## Service Issues

### dnsmasq Fails to Start

**Symptom**: `Failed to restart dnsmasq`

**Common Causes**:
1. Port 53 already in use (systemd-resolved)
2. Port 67 already in use (another DHCP server)
3. Configuration syntax error

**Solutions**:
```bash
# Check what's using port 53
sudo ss -tlnp | grep :53

# Disable systemd-resolved if conflicting
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Test dnsmasq config
sudo dnsmasq --test

# Check detailed errors
sudo journalctl -u dnsmasq -n 50

# Verify config file
cat /etc/dnsmasq.d/pxe.conf
```

### NFS Server Issues

**Symptom**: Clients can't mount NFS share

**Solutions**:
```bash
# Check NFS service
sudo systemctl status nfs-kernel-server

# Verify exports
cat /etc/exports
sudo exportfs -v

# Restart NFS
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# Check firewall
sudo iptables -L -n | grep -E '111|2049'

# Test from server
showmount -e localhost
```

### nginx Not Serving Files

**Symptom**: HTTP 404 or connection refused

**Solutions**:
```bash
# Test nginx config
sudo nginx -t

# Check nginx is running
sudo systemctl status nginx

# Verify webroot exists and has content
ls -la /var/www/html/desktop/u2404/casper/

# Check permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Test locally
curl -I http://localhost/casper/vmlinuz

# Check nginx error log
tail -f /var/log/nginx/error.log
```

---

## PXE Boot Issues

### Client Not Getting DHCP

**Symptom**: Client shows "PXE-E51: No DHCP or proxyDHCP offers"

**Solutions**:
```bash
# Verify dnsmasq is listening
sudo ss -ulnp | grep :67

# Check dnsmasq log for DHCP requests
sudo journalctl -u dnsmasq -f

# Verify interface is correct in config
cat /etc/dnsmasq.d/pxe.conf | grep interface

# Check DHCP range is correct for your network
ip addr show
```

### Client Gets DHCP But Boot Fails

**Symptom**: "PXE-E53: No boot filename received" or "TFTP timeout"

**Solutions**:
```bash
# Verify TFTP is working
echo "get /bios/pxelinux.0 /tmp/test.0" | tftp localhost

# Check TFTP files exist
ls -la /tftp/bios/pxelinux.0
ls -la /tftp/grub/bootx64.efi

# Verify TFTP root in config
grep tftp-root /etc/dnsmasq.d/pxe.conf

# Test TFTP manually
cd /tmp && tftp localhost -c get /bios/pxelinux.0
```

### UEFI Client Can't Boot

**Symptom**: UEFI client fails after getting bootx64.efi

**Solutions**:
```bash
# Verify UEFI files exist
ls -la /tftp/grub/
# Should have: bootx64.efi, grubx64.efi, grub.cfg

# Check grub.cfg paths
cat /tftp/grub/grub.cfg

# Verify kernel and initrd are accessible
ls -la /tftp/boot/casper/

# Check dnsmasq UEFI config
grep -A2 efi64 /etc/dnsmasq.d/pxe.conf
```

### Kernel Loads But Root FS Fails

**Symptom**: "Unable to mount root fs" or NFS timeout during boot

**Solutions**:
```bash
# Verify NFS exports
sudo exportfs -v | grep desktop

# Test NFS mount from another machine
sudo mount -t nfs server-ip:/var/www/html/desktop/u2404 /mnt

# Check NFS service
sudo systemctl status nfs-kernel-server

# Verify client network is in NFS_CLIENT_NETS
cat /etc/exports

# Add client network if missing
echo "/var/www/html/desktop/u2404 10.0.0.0/24(ro,sync,no_subtree_check)" | \
  sudo tee -a /etc/exports
sudo exportfs -ra
```

---

## Kiosk Mode Issues

### Firefox Not Starting in Kiosk Mode

**Symptom**: Desktop loads but Firefox doesn't auto-start

**Solutions**:
- Check if kiosk customization was applied:
```bash
# Mount squashfs and check
sudo mkdir /tmp/squash
sudo mount /var/www/html/desktop/u2404/casper/filesystem.squashfs /tmp/squash
ls /tmp/squash/etc/profile.d/99-kiosk-autostart.sh
cat /tmp/squash/etc/profile.d/99-kiosk-autostart.sh
sudo umount /tmp/squash
```

- Re-run kiosk customization:
```bash
sudo ./install.sh --force
```

### Keyboard Shortcuts Still Work

**Symptom**: Users can press F11 to exit fullscreen or Alt+Tab

**Solution**: The kiosk script should disable shortcuts. Check if it's running:
```bash
# On the PXE-booted client, check:
ps aux | grep kiosk
gsettings get org.gnome.desktop.wm.keybindings close
```

---

## Re-running Installation

### Reset and Start Fresh

```bash
# Clear completed steps (forces all steps to re-run)
sudo rm -f /var/lib/pxe-setup/completed_steps

# Or use --force flag
sudo ./install.sh --force --iso /path/to/ubuntu.iso
```

### Partial Re-run

```bash
# View completed steps
cat /var/lib/pxe-setup/completed_steps

# Remove specific step to re-run it
sudo sed -i '/kiosk/d' /var/lib/pxe-setup/completed_steps
sudo ./install.sh
```

---

## Getting Help

### Collect Debug Information

```bash
# Run with verbose logging
sudo ./install.sh --dry-run --verbose 2>&1 | tee /tmp/pxe-debug.log

# Collect service status
systemctl status dnsmasq nginx nfs-kernel-server > /tmp/services.log 2>&1

# Collect config files
tar czf /tmp/pxe-config.tar.gz \
  /etc/dnsmasq.d/pxe.conf \
  /etc/nginx/sites-enabled/pxe.conf \
  /etc/exports \
  /var/log/pxe-setup.log 2>/dev/null
```

### Log Locations

| Log | Location |
|-----|----------|
| PXE Setup | `/var/log/pxe-setup.log` |
| dnsmasq | `journalctl -u dnsmasq` |
| nginx access | `/var/log/nginx/access.log` |
| nginx error | `/var/log/nginx/error.log` |
| NFS | `journalctl -u nfs-kernel-server` |
