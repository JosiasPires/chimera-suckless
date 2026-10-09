# Chimera Linux minimal install — guia completo (humano + LLM)

Instalação do Chimera Linux numa VM/libvirt (ou PC) com: **FDE (LUKS2) senha única**,
**EFISTUB sem bootloader**, **zram**, usuário `mksh`, e desktop Wayland minimalista
**bswc + neuswc + neuwld** (https://wayland.fyi), com kernel `linux-stable` ou
kernel custom `tiny`. É o procedimento exato que resultou em **~110MB idle no tty**
(407MB no início). Funciona para bswc; adaptações para hevel/tohu são triviais
(mesma base neuswc/neuwld).

> Para LLM: execute fase por fase, valide cada saída antes de prosseguir.
> Comandos marcados `[LIVE]` rodam no live ISO como root; `[CHROOT]` via
> `chimera-chroot /media/root`. Nunca pule a verificação indicada.

## 0. Convenções e requisitos

```sh
DISK=/dev/vda        # DISCO QUE SERÁ APAGADO (wipe total). Confira com lsblk!
ESP_SIZE=1G
HOSTNAME=chimerabtw
USERNAME=alucard
USER_PASS=123123
ROOT_PASS=chimera
FDE_PASS=123123        # senha do LUKS (pode ser igual à do usuário)
TIMEZONE=America/Sao_Paulo
XKBLAYOUT=br           # keymap do console (ex: br, us)
ESP_PART=${DISK}1      # ajuste p/ nvme: ${DISK}p1
CRYPT_PART=${DISK}2    # ajuste p/ nvme: ${DISK}p2
```

Requisitos: live ISO do Chimera bootada em UEFI, rede funcionando, ~4GB RAM
para compilar (kernel tiny precisa de ~8 vCPUs e paciência). Acesso SSH ao live:
usuário `anon` senha `chimera`, root senha `chimera`.

## 1. Acesso e reconhecimento [LIVE]

```sh
ssh -o StrictHostKeyChecking=no anon@IP
su -   # senha chimera
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPE,MOUNTPOINT
ls /sys/firmware/efi   # deve existir (= boot UEFI; EFISTUB exige isso)
free -h; nproc
lspci -k | grep -i -A2 vga; ls /dev/dri/
apk update
```

## 2. Repositório `user` no live [LIVE]

O repo padrão só tem `main`. Vários pacotes (rofi, mksh, bmake) estão no `user`:

```sh
echo "v3 https://repo.chimera-linux.org/current/user" \
    >> /usr/lib/apk/repositories.d/02-repo-user.list
apk update
```

## 3. Particionamento + FDE [LIVE] ⚠️ APAGA TUDO

Layout (único viável de "FDE + EFISTUB sem bootloader": o ESP fica fora do LUKS,
pois o firmware UEFI não descriptografa nada):

```
GPT: p1 1G EFI System (C12A7328-...) + p2 resto Linux (0FC63DAF-...)
p1 -> vfat EFI, montado em /boot (kernel+initramfs ficam AQUI, legíveis)
p2 -> LUKS2 -> ext4 -> /
```

```sh
mount | grep -E "$(basename $DISK)" || true   # deve estar vazio
vgchange -an 2>/dev/null; swapoff -a 2>/dev/null
wipefs -a $DISK
sfdisk $DISK <<EOF
label: gpt
unit: sectors
${DISK}1 : start=2048, size=2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
${DISK}2 : start=2099200, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="crypt"
EOF
wipefs -a $ESP_PART $CRYPT_PART
mkfs.vfat -F32 -n EFI $ESP_PART
printf "%s" "$FDE_PASS" | cryptsetup luksFormat --type luks2 $CRYPT_PART -
printf "%s" "$FDE_PASS" | cryptsetup open $CRYPT_PART crypt -
mkfs.ext4 -L root /dev/mapper/crypt
blkid $ESP_PART $CRYPT_PART   # anote PARTUUID do crypt p/ o crypttab
```

## 4. Montagem [LIVE]

```sh
mkdir -p /media/root
mount /dev/mapper/crypt /media/root
chmod 755 /media/root
mkdir -p /media/root/boot
mount $ESP_PART /media/root/boot
df -h /media/root /media/root/boot
```

## 5. Bootstrap [LIVE]

Longo (baixa ~1.2GB). Se a rede falhar com erro de certificado, acerte o relógio
(`date -u`, `date YYYYMMDDHHmm`).

```sh
chimera-bootstrap /media/root base-full linux-stable cryptsetup-scripts efibootmgr mksh
# boot OK = "Chimera bootstrap successful", kernel 7.x instalado, /boot com
# vmlinuz-* + initrd.img-*
```

## 6. Pós-bootstrap [CHROOT]

```sh
cp /usr/lib/apk/repositories.d/02-repo-user.list \
   /media/root/usr/lib/apk/repositories.d/
chimera-chroot /media/root apk update
chimera-chroot /media/root apk add \
  foot rofi dhcpcd openssh seatd elogind dbus polkit mesa mesa-devel \
  firmware-linux firmware-linux-amd-ucode util-linux lm-sensors iw \
  wpa_supplicant acpi git clang bmake meson ninja muon pkgconf wayland-devel \
  wayland-protocols libinput-devel libxkbcommon-devel pixman-devel \
  libdrm-devel udev-devel fontconfig-devel libevdev-devel mtdev-devel curl gmake
```

Nomes corretos no Chimera (pegadinhas): `udev-devel` (não eudev),
`mesa` (não mesa-dri-gallium), sem `samu`/`fetch` (use `ninja`+`muon`,
`curl`). `rofi`/`mksh`/`bmake` vêm do repo `user`.

## 7. fstab, crypttab, identidade [CHROOT]

```sh
chimera-chroot /media/root genfstab -U / > /media/root/etc/fstab
# esperado: UUID=<ext4> / ext4 ... + UUID=<vfat> /boot vfat ...
echo "crypt PARTUUID=<PARTUUID-DO-CRYPT> none luks,discard,initramfs" \
    > /media/root/etc/crypttab
echo $HOSTNAME > /media/root/etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /media/root/etc/localtime
# keymap do console:
printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\n' "$XKBLAYOUT" \
    > /media/root/etc/default/keyboard
```

## 8. Usuários e senhas [CHROOT] ⚠️ PEGADINHA GRAVE

**NÃO use `echo user:senha | chpasswd` através do `chimera-chroot`: o stdin não
chega ao processo no chroot (sai código 0 sem gravar nada, shadow fica sem
hash e nenhum login funciona!).** Use `passwd` com stdin repetido:

```sh
chimera-chroot /media/root useradd -m -s /bin/mksh $USERNAME
chimera-chroot /media/root usermod -aG wheel,kvm,video,input,render $USERNAME
printf "%s\n%s\n" "$USER_PASS" "$USER_PASS" \
    | chimera-chroot /media/root passwd $USERNAME
printf "%s\n%s\n" "$ROOT_PASS" "$ROOT_PASS" \
    | chimera-chroot /media/root passwd root
# VALIDE: o 2o campo deve ter hash longo (~100 chars), nunca "x", "!" ou "*":
grep -E "^($USERNAME|root)" /media/root/etc/shadow | awk -F: '{print $1, length($2)}'
chimera-chroot /media/root pwck -r
```

## 9. Serviços dinit [CHROOT]

`dinitctl enable` só funciona com o dinit rodando; no chroot crie os links:

```sh
cd /media/root/etc/dinit.d/boot.d/
ln -sf /usr/lib/dinit.d/sshd sshd
ln -sf /usr/lib/dinit.d/dhcpcd dhcpcd        # ou serviço estático próprio (fase 13)
ln -sf /usr/lib/dinit.d/seatd seatd
ln -sf /usr/lib/dinit.d/elogind elogind
ln -sf /usr/lib/dinit.d/syslog-ng syslog-ng
```

## 10. zram nativo (swap ~50% RAM, zstd) [CHROOT]

Via mecanismo oficial do dinit-chimera (melhor que `rc.local`):
`/etc/dinit-zram.d/swap.conf` + serviço `zram-device@zram0` + ativação
pelo `fstab` (o helper só FORMATA; quem ativa é o `early-swap` via fstab).

```sh
ZRAM_BYTES=$(chimera-chroot /media/root awk '/MemTotal/ {print int($2*1024/2)}' /proc/meminfo)
mkdir -p /media/root/etc/dinit-zram.d
printf '[zram0]\nsize = %s\nalgorithm = zstd\nformat = mkswap -U clear %%0\n' \
    "$ZRAM_BYTES" > /media/root/etc/dinit-zram.d/swap.conf
echo "/dev/zram0 none swap sw,pri=100 0 0" >> /media/root/etc/fstab
chimera-chroot /media/root sh -c \
  "ln -sf /usr/lib/dinit.d/zram-device@zram0 /etc/dinit.d/boot.d/"
```

⚠️ Descobertas (não caia nessas):
- O helper da versão atual **não avalia expressões**: `size = (/ ram 2)` e
  backticks passam literais e falham. Use bytes literais (calcule por máquina).
- O helper **só formata** (sem shell no `format`, sem `swapon` implícito) —
  a linha do fstab é obrigatória.
- zram usa backends próprios (`ZRAM_BACKEND_ZSTD` no kernel) — `CRYPTO_ZSTD`
  sozinho NÃO serve (é só acomp; zram precisa de scomp).
- `rc.local` fica como gancho vazio. Valide com `cat /proc/swaps`
  (4G prio 100, `[zstd]`) + cold boot.

## 11. initramfs + EFISTUB sem bootloader [LIVE+CHROOT]

```sh
chimera-chroot /media/root update-initramfs -c -k all
# confira crypttab dentro do initramfs:
chimera-chroot /media/root lsinitramfs /boot/initrd.img-* | grep -E "crypttab|local-top/cryptroot"
KVER=$(ls /media/root/boot/ | sed -n 's/vmlinuz-//p')
efibootmgr --create --disk $DISK --part 1 --label "Chimera" \
  --loader "\\vmlinuz-$KVER" \
  --unicode "root=/dev/mapper/crypt rw initrd=\\initrd.img-$KVER"
efibootmgr -v | grep -A2 Chimera   # anote o número (ex: Boot0008)
```

Sem `grub`/`systemd-boot`/`limine`. Opcional (firmware chato): cópia fallback
para `\EFI\BOOT\BOOTX64.EFI`.

## 11b. UKI opcional (validado p/ o tiny; mantém EFISTUB como fallback)

Empacota kernel+initrd+cmdline num `.efi` único (pacote `systemd-boot-ukify`,
só a ferramenta — nenhum bootloader). Sem assinatura (SecureBoot off):

```sh
apk add systemd-boot-ukify
mkdir -p /boot/EFI/Linux
ukify build --linux=/boot/vmlinuz-7.2.2-tiny \
  --initrd=/boot/initrd.img-7.2.2-tiny \
  --cmdline='root=/dev/mapper/crypt rw console=ttyS0,115200 console=tty0' \
  --output=/boot/EFI/Linux/chimera-tiny.efi   # ~10MB, unsigned
efibootmgr --create --disk $DISK --part 1 --label "Chimera-UKI" \
  --loader "\\EFI\\Linux\\chimera-tiny.efi"    # sem --unicode: cmdline vai embutida
```

Ordem sugerida: UKI primeiro, EFISTUB depois, genérico por último.
Regenerar o UKI a cada rebuild de kernel/initramfs (automação futura:
hook em `/usr/lib/kernel.d/`, ver plano cports). Valide `BootCurrent` após
o boot + cold boot antes de confiar.

## 12. Stack Wayland: neuipc → neuwld → neuswc → bswc → mojito [CHROOT]

Ordem obrigatória. Env sempre (pkgconfigs em /usr/local):
`export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig`

```sh
mkdir -p /opt/wayland; cd /opt/wayland
git clone https://codeberg.org/binkd/neuipc && cd neuipc \
  && meson setup build && ninja -C build && meson install -C build && cd ..
git clone https://git.sr.ht/~shrub900/neuwld && cd neuwld \
  && (muon setup build || meson setup build) && ninja -C build \
  && (ninja -C build install || muon -C build install) && cd ..
# neuswc EXIGE PKG_CONFIG_PATH (senão: dependency 'wld' found: NO):
git clone https://git.sr.ht/~shrub900/neuswc && cd neuswc \
  && meson setup build && ninja -C build && meson install -C build && cd ..
```

**bswc sem XWayland** (pegadinhas: `DERIVE=1` força `-static` e quebra no
musl/Chimera por falta de `.a` — compile dinâmico sobrescrevendo `PKGS`;
não há target `install`, copie na mão):

```sh
git clone https://codeberg.org/binkd/bswc && cd bswc
bmake 'PKGS=neuipc swc wayland-server xkbcommon libinput pixman-1 libdrm wld libudev'
cp bswc bswcctl /usr/local/bin/   # dentro do chroot = /media/root/usr/local/bin/
```

Com XWayland: instale `libxcb-* xcb-util-wm` e compile sem sobrescrever `PKGS`.

```sh
# mojito: use gmake (não bmake) e inclua pixman+fontconfig (wld.pc incompleto):
git clone https://git.sr.ht/~dlm/mojito && cd mojito \
  && gmake 'PKGS=wayland-client wld pixman-1 fontconfig' && cp mojito /usr/local/bin/
# wawa (wallpaper): bmake && cp wawa /usr/local/bin/
git clone https://codeberg.org/sewn/wawa.git && cd wawa && bmake && cp wawa /usr/local/bin/
# hst (terminal wayland; binário chama-se st-wl; precisa de fonte, ex: Liberation):
git clone https://git.sr.ht/~dlm/hst && cd hst && bmake && cp st-wl /usr/local/bin/
```

## 13. Barra, configs, wallpaper [CHROOT]

- `bard/` (dentro do repo bswc) mostra workspaces via `neuipc` para o mojito
  (`%{l}esq%{c}centro%{r}dir`, formato lemonbar). Exige `bswcctl` no PATH
  (upstream usa `/home/binkd/bin` fixo — ajuste). Alternativa mínima sem bard:
  loop shell `while :; do date; ...; done | mojito ...`.
- `bswc.conf`: copie `src/bswc.conf.example` para `/etc/bswc/bswc.conf` e
  `~/.config/bswc/bswc.conf`; ajuste `spawn` (foot/st-wl/rofi). Nota: `bswcctl
  reload` NÃO recarrega keybinds — precisa reiniciar o compositor.
- Sessão (`~/bin/start-bswc.sh`): suba o compositor PRIMEIRO e só lance
  `wawa`/`mojito` **depois do socket Wayland existir** (senão morrem mudos —
  foi exatamente o bug "tela preta" que vimos):
  `swc-launch bswc &` → espera `$XDG_RUNTIME_DIR/wayland-*` → exporta
  `WAYLAND_DISPLAY` → `wawa fill ~/Pictures/wallpaper.jpg &` → `bar | mojito &` → `wait`.
- Wallpaper: `curl -L -o ~/Pictures/wallpaper.jpg <URL>`.
- `foot.ini` mínimo em `~/.config/foot/` se usar foot.

## 14. Desmontar e primeiro boot

```sh
sync; umount /media/root/boot; umount /media/root
cryptsetup close crypt
reboot   # NUNCA `virsh destroy` com writes pendentes no ESP!
```

No console: senha LUKS → login. SSH volta via dhcp.

## 15. Dieta pós-instalação (o que nos levou 407MB → ~110MB)

Ordem de custo-benefício (tudo reversível; valide com `free` + cold boot a cada passo):

1. `apk del fastfetch` + instalar `pfetch` (script shell, `curl` do GitHub).
2. Desabilitar serviços: `dinitctl stop X` + `ln -sf /dev/null /etc/dinit.d/X`
   (máscara lida no boot). Testados OFF sem quebrar nada: `chrony`+`chronyd`,
   `syslog-ng`, `polkitd`, `dbus-daemon`, `elogind`, `dinit-dbus`.
   ⚠️ Efeito: `turnstiled` reclama no console
   (`pam_elogind... failed to connect`) — cosmético; silencie comentando a
   linha `pam_elogind.so` em `/usr/lib/pam.d/turnstiled` e `system-login`
   (backup em `/root/pam-bak/`).
3. Autostart de usuário: remover links de `/usr/lib/dinit.d/user/boot.d/`
   (backup em `/root/user-boot.d-bak/`): `dbus-daemon`, `pipewire`,
   `pipewire-pulse`, `wireplumber` + script `~/bin/audio on|off|status`
   (lança direto, sem dinit — instância de usuário nem sempre existe no SSH).
4. Rede estática: serviço dinit próprio (`ip addr/route replace`, sem flush
   para não derrubar o SSH) + `/etc/resolv.conf` estático; mascarar `dhcpcd`.
5. SSH enxuto: compilar dropbear (`--disable-syslog` REMOVE a flag `-E`! serviço
   precisa ser sem `-E`), chaves `dropbearkey`, serviço dinit `-F -p 22 -r key`;
   migre com fallback (sobe na 2222, testa, vira 22, desliga openssh).
6. `vm.swappiness=120` (bom par p/ zram) em `/etc/sysctl.conf`.
7. Gettys: `dinitctl stop agetty-service@tty{3..6}` funciona na sessão, mas
   voltam no boot por mecanismo não identificado (não é o `dinit-agetty`;
   máscaras `/dev/null` não seguram) — quirk de ~5MB, documentado como tal.

## 16. Kernel tiny (opcional, avançado — economizou ~240MB aqui)

Só tente com fallback (entry genérica) e tempo livre. Requer no target:
`apk add gcc flex bison elfutils-devel openssl-devel perl bash binutils gsed`
(o `sed` do Chimera é busybox e quebra o build do kernel — use um dir com
`ln -s gsed sed` no **início do PATH** ao compilar; `objcopy` vem no binutils).

```sh
cd /opt/kernel
curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.2.tar.xz
tar xf linux-7.2.2.tar.xz; cd linux-7.2.2
make tinyconfig
./scripts/config --set-str LOCALVERSION "-tiny" -e <LISTA> && make olddefconfig
```

⚠️ **Armadilhas reais encontradas** (cada uma custou um ciclo de rescue):
- `scripts/config` usa `#!/bin/bash` — sem bash, falha silenciosa (exit 127).
- `tinyconfig` é **32-bit por padrão** → `-e 64BIT` (firmware x64 rejeita com `Unsupported`).
- `olddefconfig` **derruba símbolos com dependência não atendida sem avisar**:
  verifique cada um com `grep CONFIG_X=y .config` após cada rodada. Cadeias
  que morderam: `BLOCK` (p/ VIRTIO_BLK/DM/EXT4), `MULTIUSER` (p/ SECURITY→YAMA),
  `NAMESPACES` (p/ UTS/IPC/PID/NET_NS), `SYSVIPC` (p/ IPC_NS).
- Stale archives após remover subsistemas (`built-in.a` corrompidos):
  `make clean` (preserva `.config`) + rebuild total.
- Lista que funcionou nesta VM (tudo `=y`, deps resolvidas via olddefconfig):
  SMP KVM_GUEST PARAVIRT CGROUPS SECCOMP EFI EFI_STUB EFIVAR_FS RELOCATABLE
  RANDOMIZE_BASE PCI VIRTIO* (BLK/NET/CONSOLE/BALLOON/PCI/MENU) DRM*
  (VIRTIO_GPU incl.) FB/EFI/VESA FRAMEBUFFER_CONSOLE VT/VT_CONSOLE VGA/DUMMY
  INPUT/KEYBOARD/EVDEV ATKBD SERIO_I8042 USB_* HID* ATA/ATA_PIIX BLK_DEV_DM
  DM_CRYPT EFI/MSDOS_PARTITION EXT4 VFAT NLS_* TMPFS PROC SYSFS DEVTMPFS(+MOUNT)
  BLK_DEV_INITRD RD_GZIP/XZ/ZSTD CRYPTO(+AES(NI)/XTS/SHA256/ZSTD) NET/INET/IPV6/
  PACKET/UNIX BPF_SYSCALL RTC*/CMOS ACPI/BUTTON SERIAL_8250(+CONSOLE) HW_RANDOM(+
  VIRTIO) TTY UNIX98_PTYS PRINTK SWAP ZRAM ZSMALLOC BINFMT_ELF/SCRIPT/MISC
  FILE_LOCKING INOTIFY_USER SIGNALFD TIMERFD EPOLL EVENTFD CGROUP_SCHED MEMCG(
  +SWAP) BLK_CGROUP(+IOCOST) PIDS/DEVICE/MISC/BPF KEXEC(+FILE) SECURITY+YAMA
  COREDUMP SYSVIPC POSIX_MQUEUE NAMESPACES+UTS/IPC/PID/NET FUTEX(+PI) MEMFD
  AIO SND(+TIMER/PCM/HWDEP/SEQ/RAWMIDI/JACK/HDA_INTEL/codecs generics) MTRR
  X86_PAT HYPERVISOR_GUEST MAGIC_SYSRQ. Sem USB/ATA na 2a versão (nada USB/SATA
  na VM) + `64BIT`.
- `BINFMT_*`, `FILE_LOCKING` (cryptsetup morre sem), controllers de cgroup
  (script `cgroups.sh` falha com lista vazia por causa do `set -e`!), `FUTEX`
  (pipewire morre com ENOSYS), `MEMFD`, `EVENTFD` — todos ausentes no tinyconfig
  e exigidos pelo userspace moderno. `KEXEC/YAMA/COREDUMP/BINFMT_MISC` calam o
  helper `sysctl` do dinit (ou verifique se ele tolera — aqui preferimos ligar).
- Instalar: `make modules_install` (cria `/lib/modules/<ver>` p/ update-initramfs),
  `cp arch/x86/boot/bzImage /boot/vmlinuz-<ver>`, `sync`,
  `sha256sum` origem×destino (OBRIGATÓRIO — destroy sem sync já nos queimou),
  `update-initramfs -c -k <ver>` (6.5MB vs 73MB; confira `crypttab` dentro),
  entry `efibootmgr` nova **mantendo a antiga**, teste via `efibootmgr -n`
  (one-shot) + console serial antes de inverter o `BootOrder`.

## 17. Debug de boot (caixa de ferramentas validada)

- `virsh screenshot` + leitura da imagem (VGA).
- `virsh console` (serial; **sem scrollback** — anexe ANTES do evento!).
- `virsh send-key` (+ `qemu-monitor-command --hmp "sendkey <tecla> <ms>"`
  para segurar ESC e abrir o Boot Manager; `send-key A B` em uma chamada = acorde).
- `efibootmgr -n N` (one-shot), `-o` (ordem), console= invertida:
  **`/dev/console` é o ÚLTIMO `console=`** — com `tty0 ... ttyS0`, prompt LUKS
  some do VGA! Use `console=ttyS0,115200 console=tty0` p/ prompt no VGA.
- `dinit_early_debug=1` (mostra o 1o serviço que falha), `break=top`
  (shell no initramfs), `rdinit=/bin/sh`, SysRq via HMP (`sendkey alt-sysrq-w/t`).
- Validade do binário EFI em Python: magic `MZ` em 0x0, `machine==0x8664`,
  `opt_magic==0x20b` (i386=`0x14c`/`0x10b` = rejeitado).
- senhas via console: `virsh send-key KEY_1..` (PS/2) ou digitação no serial.

## 18. Medição honesta

Sempre: sem sessão gráfica, `echo 3 > /proc/sys/vm/drop_caches`, `free -m`,
top RSS (`ps -eo rss,comm --sort=-rss`). Desconte ~17MB por sessão SSH ativa
(e cada login SSH pode puxar serviços de usuário via turnstile!). Compare por
`MemAvailable`, não só `used`.
