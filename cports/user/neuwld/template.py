# Build validado localmente via cbuild (x86_64).
# Se o meson.build upstream nao configurar, trocar para build custom com muon.
pkgname = "neuwld"
pkgver = "0.0_git20260813"
pkgrel = 2
build_style = "meson"
hostmakedepends = [
    "meson",
    "pkgconf",
]
makedepends = [
    "freetype-devel",
    "libdrm-devel",
    "pixman-devel",
    "wayland-devel",
]
pkgdesc = "Primitive drawing library for Wayland"
license = "MIT"
url = "https://git.sr.ht/~shrub900/neuwld"
source = f"{url}/archive/554f827cadfdfcc276c709dbffa3b2b04c70cf7c.tar.gz"
sha256 = "b2bf77350f260cca046091d28f4a8af89cc495d1d983f3bbed8e2e39f5be86c1"


def post_install(self):
    self.install_license("COPYING")


@subpackage("neuwld-devel")
def _(self):
    return self.default_devel()
