# Build sem XWayland: sem xcb nas dependencias o suporte cai fora sozinho.
pkgname = "neuswc"
pkgver = "0.0_git20261002"
pkgrel = 0
build_style = "meson"
hostmakedepends = [
    "meson",
    "pkgconf",
]
makedepends = [
    "libdrm-devel",
    "libinput-devel",
    "libxkbcommon-devel",
    "neuipc-devel",
    "neuwld",
    "neuwld-devel",
    "neuwld-devel-static",
    "pixman-devel",
    "udev-devel",
    "wayland-devel",
    "wayland-protocols",
]
pkgdesc = "Library for simple tiling Wayland compositors"
license = "MIT"
url = "https://git.sr.ht/~shrub900/neuswc"
source = f"{url}/archive/d1ec3e24c7e0b7400dc5c0e4dfb7194e805a489d.tar.gz"
sha256 = "fb00eb77282f34c64be372a5e0730d86b500b27491b041c5cf63a4195cf5fae9"
# swc-launch e setuid root por design (helper de lancamento)
file_modes = {"usr/bin/swc-launch": ("root", "root", 0o4755)}


def post_install(self):
    self.install_license("LICENSE")


@subpackage("neuswc-devel")
def _(self):
    return self.default_devel()
