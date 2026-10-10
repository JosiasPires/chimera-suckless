# chimera-suckless

Instalação minimalista e reproduzível do **Chimera Linux**: FDE (LUKS2) +
EFISTUB **sem bootloader** + zram + desktop Wayland suckless
(**bswc** sobre **neuswc/neuwld**, terminal `hst`, barra `mojito`) +
kernel `tiny` opcional. Resultado medido: **~110MB idle no tty**
(contra ~400MB de uma instalação padrão com gráfico).

Nada é compilado no target: userspace e kernel vêm como `.apk` do
overlay (`cports/user/`), buildados no GitHub Actions e publicados em
`gh-pages` (ver `docs/CI.md`).

**Documentação online**: https://josiaspires.github.io/chimera-suckless/
(início, guia de instalação, CI, tabela de pacotes — gerada dos `.md`).

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
│   ├── dinit-zram-swap.conf   # zram nativo (bytes literais, zstd)
│   ├── sysctl-tiny.conf       # vm.swappiness=120
│   ├── uki-cmdline.txt        # cmdline embutida no UKI (-> /etc/kernel/cmdline-tiny)
│   ├── pos-install.sh         # dieta pós-boot (serviços, PAM, dropbear...)
│   └── tiny-kernel/     # .config validado do linux-tiny
├── cports/user/         # overlay: neuipc neuwld neuswc bswc mojito wawa
│                        #   hst pfetch linux-tiny (+hook UKI 55-tiny-uki.sh)
├── keys/ci.rsa.pub      # chave pública que assina os pacotes
├── docs/CI.md           # como o CI builda/publica + lições
└── .github/workflows/   # build-userspace.yml, build-kernel.yml, update-check.yml
```

## Repo de pacotes (gh-pages)

Publicado pelo CI em `gh-pages` (`user/x86_64/` + `APKINDEX`).
Para consumir, ative o Pages (Settings → Pages → branch `gh-pages`;
URL `https://josiaspires.github.io/chimera-suckless/user`) ou use o
raw (`https://raw.githubusercontent.com/JosiasPires/chimera-suckless/gh-pages/user`),
instale `keys/ci.rsa.pub` em `/etc/apk/keys/` e adicione a URL em
`/etc/apk/repositories.d/`. Detalhes: `GUIDE.md` seção 6b.

## Estratégia dual-kernel

- **Garantido** (fallback permanente): `linux-stable` do Chimera, intocado.
- **Primário**: `linux-tiny` do overlay (UKI `Chimera-UKI` primeiro no
  `BootOrder`); se falhar, o firmware cai no EFISTUB/genérico.
