pkgname = "neuipc"
pkgver = "0.0_git20260423"
pkgrel = 0
build_style = "meson"
hostmakedepends = [
    "meson",
    "pkgconf",
]
pkgdesc = "Lightweight Unix IPC library for Wayland compositors"
license = "ISC"
url = "https://codeberg.org/binkd/neuipc"
source = f"{url}/archive/d654f2fa0013237f1681fd1d8c6653a38c3cc753.tar.gz"
sha256 = "8b9855cec09079b15b1cd293aba139f63d0b716e7980a422f2fefc5224215042"


def post_install(self):
    self.install_license("LICENSE")


@subpackage("neuipc-devel")
def _(self):
    return self.default_devel()
