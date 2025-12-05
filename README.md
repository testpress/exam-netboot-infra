
# Secure Exam Lab (Network Boot / Diskless Systems)

This repository contains scripts and configurations for setting up a secure exam lab using network-booted, diskless workstations with a read-only operating system. The objective is to prevent any form of pre-exam tampering or installation of unauthorized software on client machines.

## Overview

This project provides:

* PXE boot setup (BIOS and UEFI)
* Read-only diskless OS image
* Centralized provisioning and updates
* Kiosk-mode browser for exams
* BIOS and network lockdown guidelines

## Architecture

```
[ Workstations ] --- PXE/DHCP ---> [ PXE/TFTP Server ]
       |                               |
       |------ Kernel + initrd via TFTP|
       |                               |
       |------- Root FS via NFS ------> [ NFS Server ]
```

## Features

* Diskless workstations (no HDD/SSD required)
* Reset on each reboot (no persistence)
* Central OS management
* Browser locked to exam mode
* Block bypass via USB or boot order
* Only exam URLs allowed at the network level

## Repository Structure

```
.
├── docs/          # Guides and diagrams
├── pxe/           # DHCP, TFTP, bootloader configs
├── rootfs/        # OS image build scripts
├── kiosk/         # Browser lockdown scripts
├── scripts/       # Helper and provisioning scripts
└── security/      # BIOS, firewall, and hardening steps
```