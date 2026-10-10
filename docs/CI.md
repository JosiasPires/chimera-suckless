# CI (GitHub Actions) — como funciona e como operar

## Segredos necessários

| Secret | Conteúdo | Como gerar |
|---|---|---|
| `APK_SIGN_KEY` | chave **privada** rsa do cports (`etc/keys/ci-*.rsa`) | `./cbuild keygen` local (nunca commitar!) |

A `.pub` correspondente fica em `keys/ci.rsa.pub` neste repo (pública, pode
commitar) e vai para `/etc/apk/keys` das máquinas que consomem o repo.

## Paridade local (rodar igual ao CI)

```sh
git clone https://github.com/chimera-linux/cports ~/cports
cp -r chimera-suckless/cports/user/. ~/cports/user/
cd ~/cports
./cbuild keygen            # só na 1a vez (ou reuse a chave existente)
./cbuild bootstrap
./cbuild pkg user/neuipc user/neuwld user/neuswc
./cbuild pkg user/bswc user/mojito user/wawa user/hst user/pfetch
```

O repo local sai em `~/cports/packages/`; sirva via HTTP e aponte o `apk`
da VM (ver GUIDE.md), com pinning `@local` para preferir nossos pacotes.

## Workflows

- `build.yml`: em push/PR que toque `cports/`. Faz bootstrap binário (sem
  exigir host musl), build dos pacotes do overlay, upload de artifact; na
  `main`, publica em `gh-pages` (repo apk consumível).
- `update-check.yml`: cron semanal, abre issue se houver versão nova.

**Status**: templates validados com build local real no host (x86_64) —
neuipc, neuwld, neuswc, bswc (+bard), mojito, wawa, hst, pfetch, todos com
`.apk` gerado. Workflows ainda não rodaram em runner real.

## linux-tiny (kernel do overlay)

- Template em `cports/user/linux-tiny/`: `FLAVOR=tiny`, só `x86_64`,
  co-instalável com `linux-stable` (sem `provides=["linux"]`), hook
  `files/55-tiny-uki.sh` (rebuild do UKI + entry `Chimera-UKI`) e
  `files/config-x86_64.tiny` (`.config` validado na VM + símbolos de
  toolchain ajustados p/ clang, igual aos kernels oficiais).
- `patches/fix-tools-makeoverrides.patch`: o `chimera-buildkernel`
  passa `CFLAGS`/`HOSTCFLAGS` (vazios) na linha de comando de **todo**
  `make`, e uma definição de command-line anula as atribuições dos
  makefiles das tools (ex. `CFLAGS := ...` de tools/lib/subcmd) — o
  build do objtool perde todos os `-I`
  (`fatal error: 'linux/compiler.h' file not found`). O patch filtra
  essas duas vars de `MAKEOVERRIDES` em `tools/Makefile`, demovendo-as
  a variáveis de ambiente (que os makefiles sobrescrevem normalmente);
  escopo restrito às tools, kernel propriamente dito intocado.
- Bump de `pkgrel` exige `CONFIG_LOCALVERSION="-<pkgrel>-tiny"` no config.
- Kernel sem módulos não gera `modules.order`, mas os hooks de kernel.d
  exigem o arquivo; o template cria um vazio em
  `usr/lib/modules/*-tiny/apk-dist/` no `install()`.

## Dual-kernel e promoção

- `linux-tiny` entra no CI **depois** que o pipeline provar-se estável
  (decisão registrada; template ainda a escrever).
- Regra permanente: o kernel **garantido** (build local + boot validado)
  fica pinado na VM; o kernel do CI publica em canal separado e só vira
  primário após teste de boot com fallback (mesmo ritual BootNext usado).

## Licoes do primeiro build local (para debug futuro)

- `makedepends` de libs: incluir runtime + `-devel` (+ `-static` se a lib
  for estática); `-devel` sozinho não traz o `.so`.
- Subpacotes `-devel`: usar `return self.default_devel()`.
- `post_install` com `self.install_license(...)` é obrigatório.
- `pkgdesc` sem parênteses; listas de deps em ordem alfabética.
- `CFLAGS` na linha de comando anula o `+=` dos Makefiles BSD — patchar
  com variável própria (`ALL_CFLAGS`) em bswc/mojito; `CPPFLAGS` não entra
  na regra implícita do bmake (wawa: `#define _GNU_SOURCE` no fonte).
- `install()` do template chama-se `install` (não `do_install`); `files/`
  não entra no sandbox (copiar no `post_extract`); `install_bin` aceita
  `name=`; `tic` precisa de `-o` para o destdir.
- Primeiro build de template com subpacote novo pode pedir
  `cbuild relink-subpkgs`; `clean` resolve caches meson travados.
