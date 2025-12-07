sudo mount -o loop ubuntu-24.04.3-desktop-amd64.iso /media

sudo cp -rf /media/* /var/www/html/desktop/u2404

sudo cp -rf /media/.disk /var/www/html/desktop/u2404

sudo umount /media
