# Build validado localmente via cbuild (x86_64).
pkgname = "pfetch"
pkgver = "0.0_git20240101"
pkgrel = 0
build_style = "makefile"
hostmakedepends = []
pkgdesc = "Minimalist system info script"
license = "MIT"
url = "https://github.com/dylanaraps/pfetch"
source = f"{url}/archive/refs/heads/master.tar.gz"
sha256 = "ccea779114c90e57c21e1a43cbcd16079f7558dd46d22810adb7c7d985a4d1a8"
# sem suite de testes upstream
options = ["!check"]


def post_install(self):
    self.install_license("LICENSE.md")
