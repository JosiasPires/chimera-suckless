# Overlay cports do chimera-suckless (fase C do projeto).
#
# Como usar (no builder, ex. o host):
#   git clone https://github.com/chimera-linux/cports ~/cports
#   cp -r chimera-suckless/cports/user/* ~/cports/user/
#   cd ~/cports && ./cbuild keygen && ./cbuild bootstrap
#   ./cbuild pkg user/neuipc user/neuswc ...   (ou bulk-pkg com a lista)
# Servir packages/ via HTTP e apontar o apk da VM p/ ele (ver GUIDE.md).
#
# Convenções deste overlay:
# - tudo em user/ (nada aqui mira main sem revisão upstream);
# - snapshots sem release: pkgver 0.0_gitYYYYMMDD + sha256 do tarball;
# - archs = ["x86_64"] até haver demanda;
# - TODO: Bard custom (nosso bard.c) entra como patches/ do bswc.
