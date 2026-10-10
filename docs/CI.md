# CI (GitHub Actions) — como funciona e como operar

## Segredos necessários

| Secret | Conteúdo | Como gerar |
|---|---|---|
| `APK_SIGN_KEY` | chave **privada** rsa do cports (`etc/keys/ci-*.rsa`) | `./cbuild keygen` local (nunca commitar!) |

No runner, além de gravar a privada em `cports/etc/keys/ci.rsa`, é
preciso registrá-la (`printf '[signing]\nkey = etc/keys/ci.rsa\n'`
em `cports/etc/config.ini`) + derivar a `.pub` via openssl — o cbuild
só conhece chave pelo config (`no signing key set` caso contrário) e
não há flag CLI para isso.

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

- `build-userspace.yml`: push/PR com path-filter nos 8 pacotes
  userspace. Bootstrap binário, build, artifact `apk-userspace`; na
  `main`, publica em `gh-pages`.
- `build-kernel.yml`: push com path-filter em `cports/user/linux-tiny/`
  + manual. Build só do `user/linux-tiny` (`timeout-minutes: 120`),
  artifact `apk-kernel`; na `main`, publica na mesma `gh-pages`
  (`keep_files: true`). Sem trigger em PR (economiza ~30min de runner).
- `update-check.yml`: cron semanal (inclui `user/linux-tiny`), abre
  issue se houver versão nova.
- `publish.yml` (repo único): roda ao fim de cada build (`workflow_run`)
  ou manual; baixa os artifacts mais recentes dos dois builds, faz merge,
  regenera o índice (`cbuild index`) e publica. **Nunca publique por
  workflow de build separado** — cada build gera índice só com seus
  pacotes e clobbera o índice full (foi exatamente o bug `no such
  package` no primeiro teste do zero: índice de 771b vs 3495b).
  O job de publish também precisa de `bubblewrap` instalado
  (`cbuild index` chama bwrap).

**Status**: primeiro verde em ambos (userspace ~minutos, kernel ~12min
no runner gratuito de 4 cores — sem necessidade de otimizar por ora).
Secret `APK_SIGN_KEY` cadastrado.

## Licoes do CI (runners hospedados Ubuntu)

- **Signing key**: gravar a privada em `cports/etc/keys/` não basta; o
  cbuild só a reconhece via `[signing] key = etc/keys/ci.rsa` no
  `etc/config.ini` (sem flag CLI). Erro típico: `no signing key set`
  no bootstrap. Derivar a `.pub` com openssl no mesmo step.
- **User namespaces bloqueados**: runners têm
  `apparmor_restrict_unprivileged_userns=1` → `bwrap` falha com
  `setting up uid map: Permission denied`. Fix: um step com
  `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`
  antes do bootstrap (com `sudo` o sysctl é permitido).
- **Symlinks de subpacote**: o overlay precisa commitar os links
  `<pkg>-devel -> <pkg>` (convenção do cports); sem eles,
  `subpackage ... is missing a symlink` e o bulk falha. `cp -r` no
  workflow preserva symlinks.
- **Linter**: o cbuild exige `flake8` ou `ruff` (`auto`); instalar ruff
  (binário estático) no `host deps` deixa o resultado determinístico
  entre imagens de runner.

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
