# Notas: usa gmake (nao bmake); PKGS inclui pixman-1+fontconfig porque o
# wld.pc upstream nao os puxa sozinho (ver GUIDE.md).
pkgname = "mojito"
pkgver = "0.0_git20260830"
pkgrel = 0
build_style = "makefile"
make_cmd = "gmake"
make_build_args = ["PKGS=wayland-client wld pixman-1 fontconfig"]
hostmakedepends = [
    "gmake",
    "pkgconf",
]
makedepends = [
    "fontconfig-devel",
    "neuwld-devel",
    "neuwld-devel-static",
    "pixman-devel",
    "wayland-devel",
    "wayland-protocols",
]
pkgdesc = "Featherweight lemonbar-compatible bar for Wayland"
license = "ISC"
url = "https://git.sr.ht/~dlm/mojito"
source = f"{url}/archive/5e6a307ec812ce6d7ecd66916cf4658afb19420e.tar.gz"
sha256 = "b011de518824fed192dd5eb05dfce492a9a9e0de81afd22bf7bb1a89e3e9af40"
# sem suite de testes upstream
options = ["!check"]


def post_install(self):
    self.install_license("LICENSE")
