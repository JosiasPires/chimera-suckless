# Notas: binario instalado chama-se st-wl (nao hst). O target install roda
# `tic -sx` (terminfo); se quebrar o sandbox, fazer do_install manual com
# TERMINFO apontando p/ destdir.
pkgname = "hst"
pkgver = "0.0_git20260805"
pkgrel = 0
build_style = "makefile"
make_cmd = "bmake"
hostmakedepends = [
    "bmake",
    "pkgconf",
]
makedepends = [
    "fontconfig-devel",
    "freetype-devel",
    "libdrm-devel",
    "libxkbcommon-devel",
    "ncurses-devel",
    "neuwld",
    "neuwld-devel",
    "neuwld-devel-static",
    "wayland-devel",
    "wayland-protocols",
]
pkgdesc = "Wayland-native terminal emulator"
license = "MIT"
url = "https://git.sr.ht/~dlm/hst"
source = f"{url}/archive/5906386421930127f450c3450a4600536e4cd5c6.tar.gz"
sha256 = "0a830335d4db5bd08c266d82c49f5c975698ca285c27cc77b734d117ec041627"
# sem suite de testes upstream
options = ["!check"]


def post_install(self):
    self.install_license("LICENSE")


def install(self):
    # install upstream ignora DESTDIR no tic e nao substitui VERSION;
    # fazemos na mao (ver GUIDE.md)
    self.install_bin("st-wl")
    man = (self.srcdir / "st-wl.1").read_text().replace("VERSION", "0.8.2")
    (self.srcdir / "st-wl-fixed.1").write_text(man)
    self.install_man("st-wl-fixed.1", name="st-wl.1")
    self.install_dir("usr/share/terminfo")
    self.do(
        "tic",
        "-sx",
        "-o",
        str(self.chroot_destdir / "usr/share/terminfo"),
        "st-wl.info",
    )
