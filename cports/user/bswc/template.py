# Notas:
# - Upstream nao tem target install: do_install copia na mao (igual fizemos).
# - Build dinamico sem X11 (DERIVE=1 original forca -static, que quebra no
#   musl por falta de .a; aqui passamos so o PKGS_CORE).
# - bard.c em files/ e nossa versao custom (workspaces p/ mojito); compilado
#   junto no do_install.
pkgname = "bswc"
pkgver = "0.0_git20260520"
pkgrel = 0
build_style = "makefile"
make_cmd = "bmake"
make_build_args = [
    "PKGS=neuipc swc wayland-server xkbcommon libinput pixman-1 libdrm wld libudev"
]
hostmakedepends = [
    "bmake",
    "pkgconf",
]
makedepends = [
    "fontconfig-devel",
    "libdrm-devel",
    "libinput-devel",
    "libxkbcommon-devel",
    "neuipc",
    "neuipc-devel",
    "neuswc",
    "neuswc-devel",
    "neuwld-devel",
    "neuwld-devel-static",
    "pixman-devel",
    "udev-devel",
    "wayland-devel",
]
pkgdesc = "Simple dynamic-tiling Wayland compositor"
license = "ISC"
url = "https://codeberg.org/binkd/bswc"
source = f"{url}/archive/f2d175af1c69a4ae75a40f8b31e60c1da8f45dd4.tar.gz"
sha256 = "974e23ec97ab0494ed0bbfe572821c85d2d1c1083727b577537effabd1171eab"
# sem suite de testes upstream
options = ["!check"]


def post_install(self):
    self.install_license("LICENCE")


def post_extract(self):
    # files/ nao entra no sandbox: traz bard.c p/ a arvore p/ compilar
    self.cp(self.files_path / "bard.c", self.srcdir / "bard.c")


def install(self):
    self.install_bin("bswc")
    self.install_bin("bswcctl")
    # bard: nossa versao custom (workspaces p/ mojito); "bard" colidiria
    # com o diretorio bard/ do upstream, entao compila com outro nome
    self.do("cc", "-O2", "-std=c99", "-Wall", "-o", "bard.bin", "bard.c")
    self.install_bin("bard.bin")
    self.mv(self.destdir / "usr/bin/bard.bin", self.destdir / "usr/bin/bard")
