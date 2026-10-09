# chimera-suckless

Instalação minimalista e reproduzível do **Chimera Linux**: FDE (LUKS2) +
EFISTUB **sem bootloader** + zram + desktop Wayland suckless
(**bswc** sobre **neuswc/neuwld**, terminal `hst`, barra `mojito`) +
kernel custom `tiny` opcional. Resultado medido: **~110MB idle no tty**
(contra ~400MB de uma instalação padrão com gráfico).

Funciona em **VM e em máquina real** (no hardware real, gere o `.config` do
kernel via `localmodconfig` a partir do genérico — ver `GUIDE.md`).

## Uso rápido

Baixe só o instalador e rode como root no live ISO:

```sh
curl -fsSLO https://raw.githubusercontent.com/JosiasPires/chimera-suckless/main/install.sh
sh install.sh
```

> Leia o script antes de rodar como root. Ele pergunta tudo
> (disco, usuário/senhas, hostname, timezone, keymap, terminal, XWayland,
> áudio, launcher, wallpaper, rede, kernel) e busca as configs sempre
> atualizadas deste repo (`configs/`), com fallback local.

Ou clone tudo:

```sh
git clone https://github.com/JosiasPires/chimera-suckless
```

## Layout

```
chimera-suckless/
├── README.md            # este arquivo
├── LICENSE              # MIT
├── GUIDE.md             # guia completo, fase a fase (humano + LLM)
├── install.sh           # instalador interativo (live ISO, como root)
├── configs/             # dotfiles e serviços, versionados separado do script
│   ├── bswc.conf        # atalhos Shift (sem Meta), spawn st-wl/rofi
│   ├── bar.sh           # barra mínima p/ mojito (data + mem), sem bard
│   ├── start-bswc.sh    # sobe compositor e só então wawa+mojito (via socket)
│   ├── audio            # audio on|off|status (pipewire sob demanda)
│   ├── foot.ini         # (se preferir foot ao hst)
│   ├── net-static.sh + net-static.service
│   ├── dinit-zram-swap.conf   # zram nativo ([zram0] size=(/ ram 2), zstd)
│   ├── sysctl-tiny.conf       # vm.swappiness=120
│   ├── uki-cmdline.txt        # cmdline embutida no UKI
│   ├── pos-install.sh         # dieta pós-boot (serviços, PAM, dropbear...)
│   └── tiny-kernel/     # .config validado + lista de símbolos mandatórios
└── cports/              # overlay de pacotes (fase seguinte)
    └── user/            # templates: neuipc, neuwld, neuswc, bswc, ...
```

## Estratégia dual-kernel

- **Garantido** (fallback permanente): kernel compilado e validado por nós
  (`configs/tiny-kernel/config-tiny`), entry EFI própria + genérica de rescue.
- **Primário**: build do GitHub Actions, mais recente; se falhar, o BootOrder
  cai sozinho no garantido.

## Pacotes (cports)

Templates em `cports/user/` geram `.apk` assinados (repo local via HTTP na
instalação; `pinning` prefere os nossos). Guia de contribuição futura ao
cports oficial: versões estáveis, `black`/`ruff`, sem snapshots.

## Status

Instalador + guia funcionais (testados em VM libvirt). Kernel tiny validado
com 3+ cold boots. Dieta e UKI documentados no GUIDE.
