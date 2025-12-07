sudo cp ./bios/com32/elflink/ldlinux/ldlinux.c32  /tftp/bios
sudo cp ./bios/com32/libutil/libutil.c32          /tftp/bios
sudo cp ./bios/com32/menu/menu.c32                /tftp/bios
sudo cp ./bios/com32/menu/vesamenu.c32            /tftp/bios
sudo cp ./bios/core/pxelinux.0                    /tftp/bios
sudo cp ./bios/core/lpxelinux.0                   /tftp/bios



    sudo cp ~/Downloads/grub/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed  /tftp/grubx64.efi
    sudo cp ~/Downloads/shim/usr/lib/shim/shimx64.efi.signed  /tftp/grub/bootx64.efi


    

    sudo cp /var/www/html/desktop/u2204/boot/grub/grub.cfg  /tftp/grub/
    sudo cp /var/www/html/desktop/u2404/boot/grub/grub.cfg  /tftp/grub/
    sudo cp /var/www/html/desktop/u2204/boot/grub/font.pf2 /tftp/grub/
    sudo cp /var/www/html/desktop/u2404/boot/grub/font.pf2 /tftp/grub/

    

    sudo cp /var/www/html/desktop/u2404/casper/vmlinuz      /tftp/boot/casper
    sudo cp /var/www/html/desktop/u2404/casper/initrd       /tftp/boot/casper



    sudo ln -s /tftp/boot  /tftp/bios/boot



    sudo mkdir /tftp/bios/pxelinux.cfg





