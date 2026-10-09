pkgname = "wawa"
pkgver = "0.0_git20261004"
pkgrel = 0
build_style = "makefile"
make_cmd = "bmake"
hostmakedepends = [
    "bmake",
    "pkgconf",
]
makedepends = [
    "linux-headers",
    "wayland-devel",
    "wayland-protocols",
]
pkgdesc = "Simplest wallpaper utility for Wayland"
license = "MIT"
url = "https://codeberg.org/sewn/wawa"
source = f"{url}/archive/2d4debc37d4541e24223fceff1496cbd8f8f5d5d.tar.gz"
sha256 = "14bcb0a1b317dbbfd270747a0e62cdbf5f3b62e8aae565fcde73a1fb0c2e8491"
# sem suite de testes upstream
options = ["!check"]


def post_install(self):
    self.install_license("LICENSE")
