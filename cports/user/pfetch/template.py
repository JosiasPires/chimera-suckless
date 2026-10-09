# ESQUELETO NÃO TESTADO — validar com `./cbuild lint user/pfetch`
# e `./cbuild pkg user/pfetch` antes de usar.
pkgname = "pfetch"
pkgver = "0.0_git20240101"
pkgrel = 0
pkgdesc = "Minimalist system info script"
license = "MIT"
url = "https://github.com/dylanaraps/pfetch"
source = f"{url}/archive/refs/heads/master.tar.gz"
# TODO: trocar por release estável + sha256 real (cbuild update-check ajuda)
sha256 = "TODEF"
options = ["!check", "!strip"]


def do_install(self):
    self.install_bin("pfetch")
