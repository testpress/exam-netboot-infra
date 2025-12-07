sudo cp ~/Downloads/bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot/bios

sudo cp ~/Downloads/bios/com32/libutil/libutil.c32 /var/lib/tftpboot/bios

sudo cp ~/Downloads/bios/com32/menu/menu.c32 /var/lib/tftpboot/bios

sudo cp ~/Downloads/bios/com32/menu/vesamenu.c32 /var/lib/tftpboot/bios

sudo cp ~/Downloads/bios/core/pxelinux.0 /var/lib/tftpboot/bios

sudo cp ~/Downloads/bios/core/lpxelinux.0 /var/lib/tftpboot/bios

sudo cp ~/Downloads/grub/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed /var/lib/tftpboot/grubx64.efi

sudo cp ~/Downloads/shim/usr/lib/shim/shimx64.efi.signed /var/lib/tftpboot/grub/bootx64.efi

sudo cp /var/www/html/desktop/u2404/boot/grub/grub.cfg /var/lib/tftpboot/grub/
sudo cp /var/www/html/desktop/u2404/boot/grub/font.pf2 /var/lib/tftpboot/grub/
sudo mkdir -p /var/lib/tftpboot/boot/casper

sudo cp /var/www/html/desktop/u2404/casper/vmlinuz /var/lib/tftpboot/boot/casper

sudo cp /var/www/html/desktop/u2404/casper/initrd /var/lib/tftpboot/boot/casper
sudo ln -s /var/lib/tftpboot/boot /var/lib/tftpboot/bios/boot
sudo mkdir -p /var/lib/tftpboot/bios/pxelinux.cfg

sudo nano /var/lib/tftpboot/bios/pxelinux.cfg/default
