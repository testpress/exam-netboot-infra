# PXE Server Setup

Production-ready PXE server installer for secure exam lab environments.

## Quick Start

### One-Liner Installation

```bash
curl -fsSL https://raw.githubusercontent.com/testpress/exam-netboot-infra/main/pxe-server/dist/install.sh | sudo bash -s -- -i /root/ubuntu-24.04.3-desktop-amd64.iso -y
```

### Local Installation

```bash
# Clone the repository
git clone https://github.com/your-org/exam-netboot-infra.git
cd exam-netboot-infra/pxe-server

# Build the installer
./build.sh

# Run with dry-run first to see what will happen
sudo ./dist/install.sh --dry-run --verbose --iso /path/to/ubuntu.iso

# Run for real
sudo ./dist/install.sh --iso /path/to/ubuntu.iso
```

## Prerequisites

- **Ubuntu 22.04 Server** (fresh install recommended)
- **Ubuntu 24.04 Desktop ISO** ([download here](https://ubuntu.com/download/desktop))
- **Root access** (sudo)
- **Network connectivity** (for package installation)
- **15GB+ free disk space**

## Installation Options

| Option | Description |
|--------|-------------|
| `-i, --iso PATH` | Path to Ubuntu Desktop ISO (required first time) |
| `-c, --config FILE` | Path to config file |
| `--no-kiosk` | Disable kiosk mode customization |
| `--dry-run` | Show what would happen without making changes |
| `--skip-packages` | Skip apt package installation |
| `--force` | Force re-run of completed steps |
| `-v, --verbose` | Enable debug output |
| `-y, --yes` | Non-interactive mode |
| `-h, --help` | Show help |

## Configuration

### Using a Config File

```bash
# Create config directory
sudo mkdir -p /etc/pxe-server

# Copy example config
sudo cp config/pxe-server.conf.example /etc/pxe-server/config.conf
sudo cp config/secrets.conf.example /etc/pxe-server/secrets.conf

# Secure the secrets file
sudo chmod 600 /etc/pxe-server/secrets.conf

# Edit as needed
sudo vim /etc/pxe-server/config.conf
sudo vim /etc/pxe-server/secrets.conf
```

### Key Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `ISO_PATH` | `/root/ubuntu-24.04.3-desktop-amd64.iso` | Path to Ubuntu ISO |
| `DHCP_RANGE_START` | `10.0.0.170` | Start of DHCP range |
| `DHCP_RANGE_END` | `10.0.0.200` | End of DHCP range |
| `NFS_CLIENT_NETS` | `10.0.0.0/24` | Networks allowed for NFS |
| `ENABLE_KIOSK` | `true` | Enable kiosk mode |
| `KIOSK_URL` | `https://lmsdemo.testpress.in` | URL for kiosk browser |

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
         │         ISO Contents (HTTP)          │
         │◄─────────────────────────────────────┤
         │                                      │
         ▼                                      ▼
   Kiosk Browser                          Services:
   (Exam Mode)                            - dnsmasq (DHCP+TFTP)
                                          - nginx (HTTP)
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
│   ├── grubx64.efi
│   └── grub.cfg
└── boot/casper/                # Kernel and initrd
    ├── vmlinuz
    └── initrd

/var/www/html/desktop/u2404/    # HTTP webroot (ISO contents)
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
sudo systemctl status dnsmasq nginx nfs-kernel-server

# View dnsmasq logs
sudo journalctl -u dnsmasq -n 50

# Test TFTP
tftp localhost -c get /bios/pxelinux.0

# Test HTTP
curl -I http://localhost/casper/vmlinuz

# Check NFS exports
exportfs -v
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
