#!/bin/sh
# install.sh (chimera-suckless) — instalação interativa do Chimera minimalista
# (FDE + EFISTUB sem bootloader + zram + bswc/neuswc/neuwld).
# RODE COMO ROOT NO LIVE ISO. Leia o GUIDE.md antes.
# POSIX sh. Revise cada fase (ENTER continua, Ctrl-C aborta).
set -u

say() { printf '\n=== %s ===\n' "$*"; }
ask() { # ask VAR "Pergunta" "default"
    _v="$1"; _q="$2"; _d="$3"
    printf '%s [%s]: ' "$_q" "$_d"
    IFS= read -r _a || exit 1
    [ -z "$_a" ] && _a="$_d"
    eval "$_v=\"\$_a\""
}
askpass() { # askpass VAR "Pergunta"
    _v="$1"; _q="$2"
    printf '%s: ' "$_q"
    stty -echo 2>/dev/null
    IFS= read -r _a || exit 1
    stty echo 2>/dev/null
    echo
    eval "$_v=\"\$_a\""
}
pause() { printf 'ENTER p/ continuar (Ctrl-C p/ abortar)... '; IFS= read -r _x || exit 1; }

# Configs: usa o dir local configs/ ao lado do script se existir;
# senao baixa do repo (sempre a versao mais recente).
CONFIG_REPO="${CONFIG_REPO:-https://raw.githubusercontent.com/JosiasPires/chimera-suckless/main/configs}"
SCRIPT_DIR=$(dirname "$0")
fetch_cfg() { # fetch_cfg <arquivo> <destino>
    _n="$1"; _d="$2"
    if [ -f "$SCRIPT_DIR/configs/$_n" ]; then
        cp "$SCRIPT_DIR/configs/$_n" "$_d" && return 0
    fi
    command -v curl >/dev/null 2>&1 || { echo "sem configs/ local e sem curl"; exit 1; }
    curl -fsSL "$CONFIG_REPO/$_n" -o "$_d" || { echo "falha ao buscar $_n"; exit 1; }
}

[ "$(id -u)" = "0" ] || { echo "rode como root"; exit 1; }
[ -d /sys/firmware/efi ] || { echo "sem UEFI (/sys/firmware/efi ausente), EFISTUB impossivel"; exit 1; }

say "opcoes gerais"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | head -20
ask DISK "Disco alvo (SERA APAGADO)" "/dev/vda"
ask HOSTNAME "Hostname" "chimerabtw"
ask USERNAME "Usuario" "alucard"
askpass USER_PASS "Senha do usuario"
askpass ROOT_PASS "Senha do root"
askpass FDE_PASS "Senha do FDE (LUKS)"
ask TIMEZONE "Timezone" "America/Sao_Paulo"
ask XKBLAYOUT "Keymap do console (XKB)" "br"
ask ZRAM_SIZE "Tamanho do zram" "4G"
ask WALLPAPER_URL "URL do wallpaper (vazio pula)" "https://picsum.photos/seed/chimera/1920/1080"

say "desktop (compositor fixo: bswc)"
ask TERMINAL "Terminal: foot ou hst (st-wl)" "hst"
ask XWAYLAND "Suporte XWayland? (s/n)" "n"
ask BAR_OPTS "Barra: mojito+bard / mojito-shell / nenhuma" "mojito-shell"
ask WITH_AUDIO "Instalar stack de audio? (s/n, fica desligada por padrao)" "s"
ask LAUNCHER "Launcher extra: rofi / fuzzel / nenhum" "rofi"

say "sistema"
ask SSH_FLAVOR "SSH: openssh ou dropbear(compila)?" "dropbear"
ask NET_FLAVOR "Rede: dhcp ou statica?" "statica"
ask STATIC_IP "IP estatico (se statica)" "192.168.122.187/24"
ask STATIC_GW "Gateway (se statica)" "192.168.122.1"
ask KERNEL_FLAVOR "Kernel: generico ou tiny(custom, longo)?" "generico"
ask DISABLE_EXTRA "Desabilitar chrony/syslog/polkit/dbus/elogind? (s/n)" "s"

case "$DISK" in /dev/nvme*|/dev/mmcblk*) P="p";; *) P="";; esac
ESP_PART="${DISK}${P}1"; CRYPT_PART="${DISK}${P}2"

say "CONFIRMACAO FINAL: vou apagar $DISK e instalar como $USERNAME@$HOSTNAME"
pause

# ---------- repo user + update ----------
say "repo user"
grep -q "/current/user" /usr/lib/apk/repositories.d/*.list 2>/dev/null || \
  echo "v3 https://repo.chimera-linux.org/current/user" \
    >> /usr/lib/apk/repositories.d/02-repo-user.list
apk update

# ---------- particionamento ----------
say "particionamento + LUKS"
vgchange -an 2>/dev/null; swapoff -a 2>/dev/null
wipefs -a "$DISK"
sfdisk "$DISK" <<EOF
label: gpt
unit: sectors
${DISK}${P}1 : start=2048, size=2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
${DISK}${P}2 : start=2099200, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="crypt"
EOF
wipefs -a "$ESP_PART" "$CRYPT_PART"
mkfs.vfat -F32 -n EFI "$ESP_PART"
printf "%s" "$FDE_PASS" | cryptsetup luksFormat --type luks2 "$CRYPT_PART" -
printf "%s" "$FDE_PASS" | cryptsetup open "$CRYPT_PART" crypt -
mkfs.ext4 -L root /dev/mapper/crypt
PARTUUID_CRYPT=$(blkid -s PARTUUID -o value "$CRYPT_PART")
echo "PARTUUID crypt: $PARTUUID_CRYPT"
mkdir -p /media/root
mount /dev/mapper/crypt /media/root
chmod 755 /media/root
mkdir -p /media/root/boot
mount "$ESP_PART" /media/root/boot
pause

# ---------- bootstrap ----------
say "bootstrap (demora)"
chimera-bootstrap /media/root base-full linux-stable cryptsetup-scripts efibootmgr mksh
cp /usr/lib/apk/repositories.d/02-repo-user.list \
   /media/root/usr/lib/apk/repositories.d/
chimera-chroot /media/root apk update

# ---------- pacotes ----------
say "pacotes"
PKGS="foot dhcpcd openssh seatd elogind dbus polkit mesa mesa-devel firmware-linux
firmware-linux-amd-ucode util-linux lm-sensors iw wpa_supplicant acpi git clang
bmake meson ninja muon pkgconf wayland-devel wayland-protocols libinput-devel
libxkbcommon-devel pixman-devel libdrm-devel udev-devel fontconfig-devel
libevdev-devel mtdev-devel curl gmake"
case "$TERMINAL" in foot) ;; *) PKGS=$(echo "$PKGS" | sed 's/foot //');; esac
case "$LAUNCHER" in rofi) PKGS="$PKGS rofi";; fuzzel) PKGS="$PKGS fuzzel";; esac
case "$WITH_AUDIO" in s*) PKGS="$PKGS pipewire wireplumber";; esac
# shellcheck disable=SC2086
chimera-chroot /media/root apk add $PKGS

# ---------- fstab/crypttab/identidade ----------
say "fstab/crypttab/identidade"
chimera-chroot /media/root genfstab -U / > /media/root/etc/fstab
echo "crypt PARTUUID=$PARTUUID_CRYPT none luks,discard,initramfs" > /media/root/etc/crypttab
echo "$HOSTNAME" > /media/root/etc/hostname
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /media/root/etc/localtime
printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\n' "$XKBLAYOUT" > /media/root/etc/default/keyboard

# ---------- usuarios (use passwd, NUNCA chpasswd via pipe no chroot!) ----------
say "usuarios"
chimera-chroot /media/root useradd -m -s /bin/mksh "$USERNAME"
chimera-chroot /media/root usermod -aG wheel,kvm,video,input,render "$USERNAME"
printf "%s\n%s\n" "$USER_PASS" "$USER_PASS" | chimera-chroot /media/root passwd "$USERNAME"
printf "%s\n%s\n" "$ROOT_PASS" "$ROOT_PASS" | chimera-chroot /media/root passwd root
chimera-chroot /media/root sh -c "grep -E '^($USERNAME|root)' /etc/shadow | awk -F: '{print \$1, length(\$2)}'"
echo "hash precisa ter ~100 chars (nunca 1). ENTER p/ continuar."; pause

# ---------- servicos ----------
say "servicos"
for s in seatd elogind syslog-ng; do
    chimera-chroot /media/root ln -sf "/usr/lib/dinit.d/$s" "/etc/dinit.d/boot.d/$s"
done
case "$SSH_FLAVOR" in
  openssh) chimera-chroot /media/root ln -sf /usr/lib/dinit.d/sshd /etc/dinit.d/boot.d/sshd;;
  *) echo "(dropbear instalado depois do 1o boot; mantendo openssh por ora)"; \
     chimera-chroot /media/root ln -sf /usr/lib/dinit.d/sshd /etc/dinit.d/boot.d/sshd;;
esac
case "$NET_FLAVOR" in
  dhcp) chimera-chroot /media/root ln -sf /usr/lib/dinit.d/dhcpcd /etc/dinit.d/boot.d/dhcpcd;;
  *) echo "(rede estatica configurada depois do 1o boot)"; \
     chimera-chroot /media/root ln -sf /usr/lib/dinit.d/dhcpcd /etc/dinit.d/boot.d/dhcpcd;;
esac

# ---------- zram ----------
say "zram $ZRAM_SIZE"
cat > /media/root/etc/rc.local <<EOF
#!/bin/sh
if [ -e /sys/block/zram0/disksize ]; then
  swapoff /dev/zram0 2>/dev/null
  echo 1 > /sys/block/zram0/reset 2>/dev/null || true
fi
modprobe zram 2>/dev/null || true
echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
echo $ZRAM_SIZE > /sys/block/zram0/disksize 2>/dev/null || true
mkswap /dev/zram0 2>/dev/null
swapon -p 100 /dev/zram0 2>/dev/null
exit 0
EOF
chmod +x /media/root/etc/rc.local

# ---------- initramfs + efistub ----------
say "initramfs + EFISTUB"
chimera-chroot /media/root update-initramfs -c -k all
KVER=$(ls /media/root/boot/ | sed -n 's/vmlinuz-//p' | head -1)
echo "kernel: $KVER"
efibootmgr --create --disk "$DISK" --part 1 --label "Chimera" \
  --loader "\\vmlinuz-$KVER" \
  --unicode "root=/dev/mapper/crypt rw initrd=\\initrd.img-$KVER"
pause

# ---------- wayland ----------
say "stack wayland (neuswc). Com XWayland=$XWAYLAND"
if [ "$XWAYLAND" = "s" ]; then
    chimera-chroot /media/root apk add libxcb-dev xcb-util-wm-dev
    BSWC_PKGS="neuipc swc wayland-server xkbcommon libinput pixman-1 libdrm wld libudev xcb xcb-composite xcb-ewmh xcb-icccm"
else
    BSWC_PKGS="neuipc swc wayland-server xkbcommon libinput pixman-1 libdrm wld libudev"
fi
chimera-chroot /media/root sh -c "
set -e
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig
mkdir -p /opt/wayland; cd /opt/wayland
[ -d neuipc ] || git clone https://codeberg.org/binkd/neuipc
(cd neuipc && meson setup build 2>/dev/null; ninja -C build && meson install -C build)
[ -d neuwld ] || git clone https://git.sr.ht/~shrub900/neuwld
(cd neuwld && (muon setup build || meson setup build) && ninja -C build && (ninja -C build install || muon -C build install))
[ -d neuswc ] || git clone https://git.sr.ht/~shrub900/neuswc
(cd neuswc && rm -rf build && meson setup build && ninja -C build && meson install -C build)
[ -d bswc ] || git clone https://codeberg.org/binkd/bswc
(cd bswc && bmake clean 2>/dev/null; bmake PKGS=\"$BSWC_PKGS\" && cp bswc bswcctl /usr/local/bin/)
[ -d mojito ] || git clone https://git.sr.ht/~dlm/mojito
(cd mojito && gmake clean 2>/dev/null; gmake 'PKGS=wayland-client wld pixman-1 fontconfig' && cp mojito /usr/local/bin/)
[ -d wawa ] || git clone https://codeberg.org/sewn/wawa.git
(cd wawa && bmake && cp wawa /usr/local/bin/ || true)
echo WAYLAND_STACK_OK
"
case "$TERMINAL" in
  hst) chimera-chroot /media/root sh -c \
    "cd /opt/wayland && [ -d hst ] || git clone https://git.sr.ht/~dlm/hst; cd hst && bmake && cp st-wl /usr/local/bin/";;
esac
case "$BAR_OPTS" in
  mojito-shell) : ;; # bar.sh criada abaixo
  *) echo "(adapte a barra manualmente depois)";;
esac
pause

# ---------- configs ----------
say "configs"
TERM_BIN=foot; [ "$TERMINAL" = "hst" ] && TERM_BIN=st-wl
LAUNCHER_BIN=true; [ "$LAUNCHER" = "rofi" ] && LAUNCHER_BIN="rofi -show drun"
[ "$LAUNCHER" = "fuzzel" ] && LAUNCHER_BIN="fuzzel"
chimera-chroot /media/root sh -c "mkdir -p /etc/bswc /home/$USERNAME/.config/bswc /home/$USERNAME/.config/foot /home/$USERNAME/bin /home/$USERNAME/Pictures"
cat > /media/root/etc/bswc/bswc.conf <<EOF
set motion_throttle_hz      85
set border_col_active       0x060a07
set border_col_normal       0xe6e1dc
set border_width            4
set master_width            60
set gaps                    50
set workspaces              5
bind key Return     shift           spawn       $TERM_BIN
bind key p          shift           spawn       $LAUNCHER_BIN
bind key Return     shift,ctrl      spawn       $TERM_BIN -e mksh
bind key e          shift,ctrl      quit
bind key k          shift           focus_next
bind key j          shift           focus_prev
bind key q          shift,ctrl      kill_sel
bind key space      shift           toggle_float
bind key l          shift           master_resize    50
bind key h          shift           master_resize    -50
bind key 1          shift           workspace_goto      1
bind key 2          shift           workspace_goto      2
bind key 3          shift           workspace_goto      3
bind key 4          shift           workspace_goto      4
bind key 5          shift           workspace_goto      5
bind key 1          shift,ctrl      workspace_moveto    1
bind key 2          shift,ctrl      workspace_moveto    2
bind key 3          shift,ctrl      workspace_moveto    3
bind key 4          shift,ctrl      workspace_moveto    4
bind key 5          shift,ctrl      workspace_moveto    5
bind button left    ctrl            mouse_move
bind button right   ctrl            mouse_resize
EOF
cp /media/root/etc/bswc/bswc.conf /media/root/home/$USERNAME/.config/bswc/bswc.conf
# scripts do usuario: tenta configs/ local, senao baixa do repo (sempre latest)
fetch_cfg bar.sh /media/root/home/$USERNAME/bin/bar.sh
fetch_cfg start-bswc.sh /media/root/home/$USERNAME/bin/start-bswc.sh
fetch_cfg audio /media/root/home/$USERNAME/bin/audio
if [ "$TERMINAL" = "foot" ]; then
    fetch_cfg foot.ini /media/root/home/$USERNAME/.config/foot/foot.ini
fi
fetch_cfg pos-install.sh /media/root/root/pos-install.sh
chmod +x /media/root/home/$USERNAME/bin/bar.sh \
         /media/root/home/$USERNAME/bin/start-bswc.sh \
         /media/root/home/$USERNAME/bin/audio \
         /media/root/root/pos-install.sh
chown -R "$USERNAME:$USERNAME" "/media/root/home/$USERNAME"
if [ -n "$WALLPAPER_URL" ]; then
    chimera-chroot /media/root sh -c "curl -L --max-time 60 -o /home/$USERNAME/Pictures/wallpaper.jpg '$WALLPAPER_URL'" || true
    chown "$USERNAME:$USERNAME" "/media/root/home/$USERNAME/Pictures/wallpaper.jpg" 2>/dev/null || true
fi

# ---------- extras pos-instalacao (rode no 1o boot) ----------
# (pos-install.sh ja foi buscado acima, sempre atualizado; ver configs/pos-install.sh)

# ---------- fim ----------
say "desmontando"
sync
umount /media/root/boot
umount /media/root
cryptsetup close crypt
echo
echo "OK. Reboote, digite a senha LUKS ($FDE_PASS e boot), login $USERNAME."
echo "Detalhes da dieta/kernel/debug: GUIDE.md. Pós-instalação: /root/pos-install.sh."
