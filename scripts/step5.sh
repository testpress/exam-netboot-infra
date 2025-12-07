mkdir ~/client-root
sudo unsquashfs -d ~/client-root /var/www/html/desktop/u2404/casper/minimal.squashfs

sudo tee ~/client-root/etc/profile.d/autostart.sh > /dev/null << 'EOF'
#!/bin/bash
# ultra-kiosk-x.sh
# Only Firefox allowed for user ubuntu in X session (full lockdown)

USER=ubuntu

URL="https://lmsdemo.testpress.in"
SSID="Testpress_5G"
PASSWORD="Tp@12345"

# --- Kill bootstrap process before kiosk ---
sudo pkill -f ubuntu-bootstra >/dev/null 2>&1 || true

# Only run if in X session
if [ "$DISPLAY" ]; then

    launch_firefox() {
        pkill -u "$USER" firefox >/dev/null 2>&1 || true
        export MOZ_NO_REMOTE=1
        firefox --kiosk --private-window "$URL" --new-instance &
    }

    disable_gnome_shortcuts() {
        gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "[]"
        gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "[]"
        gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up "[]"
        gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down "[]"
        gsettings set org.gnome.desktop.wm.keybindings close "[]"
        gsettings set org.gnome.desktop.wm.keybindings maximize "[]"
        gsettings set org.gnome.desktop.wm.keybindings minimize "[]"
        gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
        gsettings set org.gnome.mutter overlay-key ''
    }

    prevent_screen_sleep() {
        xset s off
        xset -dpms
        xset s noblank
    }

    enforce_firefox_policies() {
        POLICIES_DIR="/home/$USER/.mozilla/firefox/kiosk_default/policies"
        mkdir -p "$POLICIES_DIR"
        cat > "$POLICIES_DIR/policies.json" <<EOP
{
  "policies": {
    "Homepage": "$URL",
    "HomepageIsNewTabPage": true,
    "DisableAppUpdate": true,
    "BlockAboutConfig": true,
    "DisableProfiles": true,
    "DisableDeveloperTools": true,
    "URLWhitelist": ["$URL"],
    "URLBlacklist": ["*"]
  }
}
EOP
        chown -R $USER:$USER "$POLICIES_DIR"
    }

    block_function_keys_and_terminals() {
        sleep 2
        for keycode in $(seq 67 76) 95 133 134 64 37; do
            xmodmap -e "keycode $keycode = NoSymbol" >/dev/null 2>&1
        done
        xmodmap -e "keycode 24 = NoSymbol" >/dev/null 2>&1
        xmodmap -e "keycode 64 = NoSymbol" >/dev/null 2>&1
        xmodmap -e "keycode 108 = NoSymbol" >/dev/null 2>&1
    }

    connect_wifi() {
        nmcli dev wifi connect "$SSID" password "$PASSWORD" || true
    }

    setup_network_firewall() {
        sudo iptables -F
        sudo iptables -X
        sudo iptables -P INPUT ACCEPT
        sudo iptables -P OUTPUT ACCEPT
        sudo iptables -P FORWARD ACCEPT

        sudo iptables -A INPUT -i lo -j ACCEPT
        sudo iptables -A OUTPUT -o lo -j ACCEPT

        sudo iptables -A INPUT -p udp --dport 67:69 -j ACCEPT
        sudo iptables -A OUTPUT -p udp --sport 67:69 -j ACCEPT

        sudo iptables -A INPUT -p tcp -m multiport --sports 111,2049,20048 -j ACCEPT
        sudo iptables -A INPUT -p udp -m multiport --sports 111,2049,20048 -j ACCEPT
        sudo iptables -A OUTPUT -p tcp -m multiport --dports 111,2049,20048 -j ACCEPT
        sudo iptables -A OUTPUT -p udp -m multiport --dports 111,2049,20048 -j ACCEPT
    }

    disable_gnome_shortcuts
    prevent_screen_sleep
    enforce_firefox_policies
    setup_network_firewall
    launch_firefox

    (
        while true; do
            if ! pgrep -u "$USER" firefox >/dev/null 2>&1; then
                launch_firefox
            fi
            block_function_keys_and_terminals
            sleep 1
        done
    ) &
fi
EOF

