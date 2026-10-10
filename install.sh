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
ask WALLPAPER_URL "URL do wallpaper (vazio pula)" "https://picsum.photos/seed/chimera/1920/1080"

say "desktop (compositor fixo: bswc, sem XWayland)"
ask TERMINAL "Terminal: foot ou hst (st-wl)" "hst"
ask BAR_OPTS "Barra: mojito+bard / mojito-shell / nenhuma" "mojito-shell"
ask WITH_AUDIO "Instalar stack de audio? (s/n, fica desligada por padrao)" "s"
ask LAUNCHER "Launcher extra: rofi / fuzzel / nenhum" "rofi"

say "sistema"
ask SSH_FLAVOR "SSH: openssh ou dropbear(compila)?" "dropbear"
ask NET_FLAVOR "Rede: dhcp ou statica?" "statica"
ask STATIC_IP "IP estatico (se statica)" "192.168.122.187/24"
ask STATIC_GW "Gateway (se statica)" "192.168.122.1"
ask KERNEL_FLAVOR "Kernel: generico ou tiny (pacote overlay + UKI)?" "generico"
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

# ---------- repo overlay chimera-suckless (nossos pacotes) ----------
# Pacotes assinados com keys/ci.rsa.pub; prefere Pages, cai p/ raw se o
# site ainda nao estiver ativado (Settings -> Pages -> branch gh-pages).
say "repo overlay"
OVERLAY_URL="https://josiaspires.github.io/chimera-suckless/user"
if ! curl -fsSI --max-time 15 "$OVERLAY_URL/x86_64/APKINDEX.tar.gz" >/dev/null 2>&1; then
    OVERLAY_URL="https://raw.githubusercontent.com/JosiasPires/chimera-suckless/gh-pages/user"
fi
echo "overlay: $OVERLAY_URL"
mkdir -p /media/root/etc/apk/repositories.d /media/root/etc/apk/keys
echo "$OVERLAY_URL" > /media/root/etc/apk/repositories.d/10-overlay.list
if [ -f "$SCRIPT_DIR/keys/ci.rsa.pub" ]; then
    cp "$SCRIPT_DIR/keys/ci.rsa.pub" /media/root/etc/apk/keys/
else
    curl -fsSL "https://raw.githubusercontent.com/JosiasPires/chimera-suckless/main/keys/ci.rsa.pub" \
        -o /media/root/etc/apk/keys/ci.rsa.pub || { echo "falha ao buscar chave do overlay"; exit 1; }
fi
chimera-chroot /media/root apk update || { echo "ERRO: apk update falhou (rede? repo?)"; exit 1; }
# valida que o overlay resolve (fail-fast: nao adianta seguir sem os pacotes;
# NB: apk search retorna 0 mesmo sem match, por isso testa saida nao-vazia)
[ -n "$(chimera-chroot /media/root apk search -q bswc 2>/dev/null)" ] || { echo "ERRO: overlay nao esta resolvendo pacotes (verifique URL/chave/rede)"; exit 1; }

# ---------- pacotes ----------
# (stack wayland + kernel tiny vem do overlay, mais abaixo; aqui so base)
say "pacotes"
PKGS="dhcpcd openssh seatd elogind dbus polkit mesa firmware-linux
firmware-linux-amd-ucode util-linux lm-sensors iw wpa_supplicant acpi git curl"
case "$TERMINAL" in foot) PKGS="$PKGS foot";; esac
case "$LAUNCHER" in rofi) PKGS="$PKGS rofi";; fuzzel) PKGS="$PKGS fuzzel";; esac
case "$WITH_AUDIO" in s*) PKGS="$PKGS pipewire wireplumber";; esac
# shellcheck disable=SC2086
chimera-chroot /media/root apk add $PKGS || { echo "ERRO: apk add base falhou"; exit 1; }

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
  *)
    say "rede estatica ($STATIC_IP via $STATIC_GW)"
    IFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
    [ -n "$IFACE" ] || { echo "sem interface (sem lo)!"; exit 1; }
    echo "interface: $IFACE"
    fetch_cfg net-static.sh /tmp/net-static.sh
    mkdir -p /media/root/usr/local/sbin
    sed -e "s/enp1s0/$IFACE/g" -e "s|192.168.122.187/24|$STATIC_IP|g" \
        -e "s|192.168.122.1|$STATIC_GW|g" /tmp/net-static.sh \
        > /media/root/usr/local/sbin/net-static.sh
    chmod +x /media/root/usr/local/sbin/net-static.sh
    fetch_cfg net-static.service /media/root/etc/dinit.d/net-static
    chimera-chroot /media/root ln -sf /etc/dinit.d/net-static /etc/dinit.d/boot.d/net-static 2>/dev/null || \
      chimera-chroot /media/root sh -c "mkdir -p /etc/dinit.d/boot.d && ln -sf /etc/dinit.d/net-static /etc/dinit.d/boot.d/"
    # dhcpcd fica instalado mas desligado (fallback manual se a estatica falhar)
    printf 'nameserver %s\n' "$STATIC_GW" > /media/root/etc/resolv.conf
    ;;
esac

# ---------- zram nativo (dinit-zram) ----------
say "zram nativo"
ZRAM_BYTES=$(chimera-chroot /media/root awk '/MemTotal/ {print int($2*1024/2)}' /proc/meminfo)
mkdir -p /media/root/etc/dinit-zram.d
printf '[zram0]\nsize = %s\nalgorithm = zstd\nformat = mkswap -U clear %%0\n' \
    "$ZRAM_BYTES" > /media/root/etc/dinit-zram.d/swap.conf
grep -q /dev/zram0 /media/root/etc/fstab 2>/dev/null || \
    echo "/dev/zram0 none swap sw,pri=100 0 0" >> /media/root/etc/fstab
chimera-chroot /media/root ln -sf /usr/lib/dinit.d/zram-device@zram0 /etc/dinit.d/boot.d/ 2>/dev/null || \
    chimera-chroot /media/root sh -c "mkdir -p /etc/dinit.d/boot.d && ln -sf /usr/lib/dinit.d/zram-device@zram0 /etc/dinit.d/boot.d/"
# rc.local fica como gancho vazio (zram agora é nativo)
printf '#!/bin/sh\n# gancho local (zram e gerenciado pelo dinit: zram-device@zram0).\nexit 0\n' \
    > /media/root/etc/rc.local
chmod +x /media/root/etc/rc.local

# ---------- initramfs + efistub (+ tiny opcional) ----------
say "initramfs + EFISTUB"
chimera-chroot /media/root update-initramfs -c -k all
case "$KERNEL_FLAVOR" in
  tiny*)
    say "kernel tiny via apk (overlay)"
    # cmdline ANTES do apk add: o hook 55-tiny-uki.sh exige o arquivo
    mkdir -p /media/root/etc/kernel
    fetch_cfg uki-cmdline.txt /media/root/etc/kernel/cmdline-tiny
    chimera-chroot /media/root apk add linux-tiny || { echo "ERRO: apk add linux-tiny falhou"; exit 1; }
    # hooks kernel.d rodam no chroot (00-setup, 50-initramfs, 55-tiny-uki);
    # se algo nao gerou, completa aqui:
    KVER_TINY=$(ls /media/root/boot/ | sed -n 's/vmlinuz-//p' | grep tiny | sort -V | tail -1)
    [ -n "$KVER_TINY" ] || { echo "vmlinuz tiny ausente em /boot!"; exit 1; }
    [ -f "/media/root/boot/initrd.img-$KVER_TINY" ] || \
      chimera-chroot /media/root update-initramfs -c -k "$KVER_TINY"
    echo "kernel tiny: $KVER_TINY"
    ;;
esac
KVER=$(ls /media/root/boot/ | sed -n 's/vmlinuz-//p' | head -1)
echo "kernel generic (fallback): $KVER"
# limpa entries nossas (inclusive stale de installs anteriores: mesmo label,
# ESP antigo) e recria do zero; ordem explicita no final
for _lbl in Chimera Chimera-tiny Chimera-UKI; do
  for _n in $(efibootmgr | sed -n "s/^Boot\([0-9A-Fa-f]*\)\* $_lbl.*/\1/p"); do
    efibootmgr -b "$_n" -B >/dev/null 2>&1 || true
  done
done
efibootmgr --create --disk "$DISK" --part 1 --label "Chimera" \
  --loader "\\vmlinuz-$KVER" \
  --unicode "root=/dev/mapper/crypt rw initrd=\\initrd.img-$KVER"
NUM_GENERIC=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* Chimera.*/\1/p' | head -1)
if [ -n "${KVER_TINY:-}" ]; then
  # entry EFISTUB direta do tiny (fallback; hook UKI cuida da principal)
  efibootmgr --create --disk "$DISK" --part 1 --label "Chimera-tiny" \
    --loader "\\vmlinuz-$KVER_TINY" \
    --unicode "root=/dev/mapper/crypt rw console=ttyS0,115200 console=tty0 initrd=\\initrd.img-$KVER_TINY"
  NUM_TINY=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* Chimera-tiny.*/\1/p' | head -1)
  if [ -f /media/root/boot/EFI/Linux/chimera-tiny.efi ]; then
    efibootmgr --create --disk "$DISK" --part 1 --label "Chimera-UKI" \
      --loader "\\EFI\\Linux\\chimera-tiny.efi"
    NUM_UKI=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* Chimera-UKI.*/\1/p' | head -1)
  else
    echo "AVISO: UKI nao gerado no chroot; sera criado no 1o boot pelo hook (ou rode ukify manual, GUIDE §11b)"
  fi
fi
# BootOrder explicita: UKI > tiny-direto > generico > resto (sem dupes).
# Sem isso o firmware pode bootar o generico primeiro numa NVRAM fresca.
ORDER=","
for _n in ${NUM_UKI:-} ${NUM_TINY:-} ${NUM_GENERIC:-}; do
  ORDER="$ORDER$_n,"
done
for _n in $(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' ' '); do
  case "$ORDER" in *",$_n,"*) ;; *) ORDER="$ORDER$_n,";; esac
done
ORDER=$(echo "$ORDER" | sed 's/^,//;s/,$//;s/,,*/,/g')
echo "BootOrder: $ORDER"
efibootmgr -o "$ORDER"
pause

# ---------- stack wayland (pacotes do overlay) ----------
say "stack wayland via apk (overlay)"
WLPGS="neuipc neuwld neuswc bswc mojito wawa pfetch"
case "$TERMINAL" in hst) WLPGS="$WLPGS hst";; esac
# shellcheck disable=SC2086
chimera-chroot /media/root apk add $WLPGS || { echo "ERRO: apk add wayland falhou (overlay fora do ar?)"; exit 1; }
echo "wayland via apk OK (binarios em /usr/bin, libs como dependencias)"
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
