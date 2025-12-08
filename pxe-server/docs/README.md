# PXE Server Setup

Production-ready PXE server installer for secure exam lab environments.

## Quick Start

### One-Liner Installation (Auto-Download ISO)

```bash
# Auto-download latest Ubuntu 24.04.x and install (prompts for confirmation)
curl -fsSL https://bit.ly/tpnetboot | sudo bash
```

### One-Liner with Existing ISO

```bash
# Use existing ISO, non-interactive mode
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- -i /root/ubuntu-24.04.3-desktop-amd64.iso -y
```

### Curl Examples with Options

```bash
# Specify ethernet interface (when WiFi is default route)
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --interface enp3s0 -y

# Create debug client (no key blocking, shortcuts enabled)
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- -i /root/ubuntu.iso --kiosk-debug -y

# Dry-run to see what will happen
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --dry-run --verbose

# Skip package installation (already installed)
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- -i /root/ubuntu.iso --skip-packages -y
```

### Step-by-Step Installation with Resume

The installer tracks progress in `/var/lib/pxe-setup/completed_steps`. You can run it step-by-step and resume later.

**Example workflow:**

```bash
# Step 1: See all available steps
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --list-steps
# Output shows: iso_download, static_ip, packages, directories, pxeroot, 
#               bootloaders, tftp, nfs, pxelinux, grub, dnsmasq, kiosk, services

# Step 2: Run first step only
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --step iso_download

# Step 3: Run next step manually
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --step packages

# ... or run all remaining steps at once (completed steps are skipped)
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- -y

# If something fails, fix the issue and resume
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --from-step dnsmasq

# To start completely fresh
curl -fsSL https://bit.ly/tpnetboot | sudo bash -s -- --reset
```

**Check progress at any time:**
```bash
cat /var/lib/pxe-setup/completed_steps
```

### Local Installation

```bash
git clone https://github.com/testpress/exam-netboot-infra.git
cd exam-netboot-infra/pxe-server

./build.sh
sudo ./dist/install.sh --dry-run --verbose
sudo ./dist/install.sh
```

## Prerequisites

- **Ubuntu 22.04/24.04 Server** (fresh install recommended)
- **Ubuntu 24.04 Desktop ISO** (auto-downloaded if not provided)
- **Root access** (sudo)
- **Network connectivity** (for package installation)
- **15GB+ free disk space**

## Installation Options

| Option | Description |
|--------|-------------|
| `-i, --iso PATH` | Path to Ubuntu Desktop ISO (auto-downloads if not provided) |
| `--interface NAME` | Network interface for PXE (default: auto-detect ethernet) |
| `-c, --config FILE` | Path to config file |
| `--no-kiosk` | Disable kiosk mode customization |
| `--kiosk-debug` | Disable kiosk lockdown (for debugging clients) |
| `--dry-run` | Show what would happen without making changes |
| `--skip-packages` | Skip apt package installation |
| `--force` | Force re-run of completed steps |
| `-v, --verbose` | Enable debug output |
| `-y, --yes` | Non-interactive mode |
| `-h, --help` | Show help |

### Step Control Options

| Option | Description |
|--------|-------------|
| `--list-steps` | List all steps and their completion status |
| `--step <name>` | Run only a single step |
| `--from-step <name>` | Resume from a specific step |
| `--reset` | Clear all progress and start fresh |

> **Note:** Step completion is tracked in `/var/lib/pxe-setup/completed_steps`. 
> Running the script again will skip completed steps automatically. Use `--force` to re-run or `--reset` to start fresh.

## Configuration

### Using a Config File

```bash
sudo mkdir -p /etc/pxe-server
sudo cp config/pxe-server.conf.example /etc/pxe-server/config.conf
sudo cp config/secrets.conf.example /etc/pxe-server/secrets.conf
sudo chmod 600 /etc/pxe-server/secrets.conf
sudo vim /etc/pxe-server/config.conf
```

### Key Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `ISO_PATH` | (auto-download) | Path to Ubuntu ISO |
| `PXE_ROOT` | `/srv/pxe/u2404` | NFS root for PXE files |
| `DHCP_RANGE_START` | `10.0.0.170` | Start of DHCP range |
| `DHCP_RANGE_END` | `10.0.0.200` | End of DHCP range |
| `NFS_CLIENT_NETS` | `10.0.0.0/24` | Networks allowed for NFS |
| `ENABLE_KIOSK` | `true` | Enable kiosk mode |
| `KIOSK_URL` | `https://lmsdemo.testpress.in` | URL for kiosk browser |
| `KIOSK_BLOCK_KEYS` | `true` | Block F1-F12, Super key |
| `KIOSK_DISABLE_SHORTCUTS` | `true` | Disable GNOME shortcuts |

## Architecture

```
┌─────────────────┐     DHCP/TFTP      ┌─────────────────┐
│   PXE Client    │◄───────────────────│   PXE Server    │
│   (Workstation) │                    │   (This setup)  │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         │         Kernel + Initrd (TFTP)       │
         │◄─────────────────────────────────────┤
         │                                      │
         │         Root FS (NFS)                │
         │◄─────────────────────────────────────┤
         │                                      │
         ▼                                      ▼
   Kiosk Browser                          Services:
   (Firefox + systemd auto-restart)       - dnsmasq (DHCP+TFTP)
                                          - NFS server
```

## Directory Structure

After installation:

```
/tftp/                          # TFTP root
├── bios/                       # BIOS boot files
│   ├── pxelinux.0
│   ├── pxelinux.cfg/default
│   └── *.c32
├── grub/                       # UEFI boot files
│   ├── bootx64.efi
│   └── grub.cfg
└── boot/casper/                # Kernel and initrd

/srv/pxe/u2404/                 # NFS root (ISO contents)
├── casper/
│   ├── filesystem.squashfs    # Root filesystem (customized for kiosk)
│   ├── vmlinuz
│   └── initrd
└── ...

/etc/pxe-server/                # Configuration
├── config.conf
└── secrets.conf

/var/lib/pxe-setup/             # State tracking
└── completed_steps
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues and solutions.

### Quick Debug Commands

```bash
# Check service status
sudo systemctl status dnsmasq nfs-kernel-server

# View dnsmasq logs
sudo journalctl -u dnsmasq -n 50

# Test TFTP
tftp localhost -c get /bios/pxelinux.0

# Check NFS exports
exportfs -v

# View kiosk log on client
cat /tmp/kiosk-autostart.log
```

## Development

### Building the Installer

```bash
cd pxe-server

# Edit source files in lib/ and src/
vim lib/kiosk.sh

# Rebuild
./build.sh

# Test
sudo ./dist/install.sh --dry-run
```

### Running Tests

```bash
# Install bats (if not installed)
sudo apt install bats

# Run tests
cd tests
bats test_functions.bats
```

## License

MIT License - See LICENSE file for details.
