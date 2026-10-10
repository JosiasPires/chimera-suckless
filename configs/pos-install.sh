#!/bin/sh
# pos-install.sh — rode como root no sistema instalado.
# Desabilita o que nao precisa. Uso: ./pos-install.sh [--all]
# Detalhes e reversao: ver GUIDE.md secao 15.
set -u

mask() { dinitctl stop "$1" 2>/dev/null; ln -sf /dev/null "/etc/dinit.d/$1"; }

if [ "${1:-}" = "--all" ]; then
    for s in chrony chronyd syslog-ng polkitd dbus-daemon elogind dinit-dbus sshd dhcpcd; do
        mask "$s"
    done
fi
rm -f /etc/dinit.d/boot.d/sshd /etc/dinit.d/boot.d/dhcpcd \
      /etc/dinit.d/boot.d/elogind /etc/dinit.d/boot.d/syslog-ng

# PAM: silencia pam_elogind sem dbus (backup em /root/pam-bak).
# Rode SOMENTE se dbus+elogind estiverem mascarados, e restaure se voltarem.
mkdir -p /root/pam-bak
cp /usr/lib/pam.d/turnstiled /usr/lib/pam.d/system-login /root/pam-bak/ 2>/dev/null
echo "edite /usr/lib/pam.d/turnstiled e system-login comentando a linha pam_elogind.so"

# Rede estatica (ajuste IP/GW): crie /etc/dinit.d/net-static (type=scripted,
# comandos 'ip addr replace' + 'ip route replace'), link em boot.d,
# /etc/resolv.conf estatico, depois mask dhcpcd.
# Veja configs/net-static.sh e configs/net-static.service neste repo.

# Dropbear: compile de https://matt.ucc.asn.au/dropbear/ (ATENCAO: se usar
# --disable-syslog, a flag -E deixa de existir!). Gere chaves com dropbearkey,
# crie o servico dinit '-F -p 22 -r <key>', teste na porta 2222 antes de
# virar a 22 e desligar o openssh.

# Audio: remova os links de /usr/lib/dinit.d/user/boot.d/
# (dbus-daemon, pipewire, pipewire-pulse, wireplumber) com backup, e use
# ~/bin/audio on|off (lancamento direto, sem dinit).

# Kernel tiny: `apk add linux-tiny` (hook UKI cuida de /boot+entry;
# cmdline em /etc/kernel/cmdline-tiny). Ver GUIDE.md secao 16.
# Depois: pfetch no lugar do fastfetch (`apk add pfetch`), hst no lugar
# do foot (`apk add hst`, opcional), swappiness (configs/sysctl-tiny.conf).
echo "pos-install: revise e descomente/aplique o que quiser usar"
