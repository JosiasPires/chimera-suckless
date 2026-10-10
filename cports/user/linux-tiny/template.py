# Build validado localmente via cbuild (x86_64).
# Kernel enxuto do projeto chimera-suckless (bswc/wld, sem modulos).
# .config validado em boot real (EFISTUB + UKI) na VM chimerabtw, com os
# simbolos de toolchain ajustados para clang (CC_IS_CLANG, AS_IS_LLVM,
# versoes 220108), igual aos kernels oficiais Chimera.
# Requer patches/fix-tools-subcmd-cflags.patch: o chimera-buildkernel
# passa CFLAGS vazio na linha de comando do make, o que anula o
# `CFLAGS := ...` de tools/lib/subcmd e quebra o build do objtool
# (fatal error: 'linux/compiler.h' file not found). Ver docs/CI.md.
# Co-instalavel com linux-stable (fallback); NAO fornece "linux".
# Bump de pkgrel exige CONFIG_LOCALVERSION="-<pkgrel>-tiny" no config.
pkgname = "linux-tiny"
pkgver = "7.2.2"
pkgrel = 3
archs = ["x86_64"]
build_style = "linux_kernel"
configure_args = ["FLAVOR=tiny", f"RELEASE={pkgrel}"]
make_dir = "build"
make_install_env = {"ZSTD_CLEVEL": "9"}
hostmakedepends = ["base-kernel-devel"]
depends = [
    "base-kernel",
    "efibootmgr",
    "systemd-boot-ukify",
]
pkgdesc = "Linux kernel tiny for chimera-suckless EFISTUB/UKI setups"
license = "GPL-2.0-only"
url = "https://kernel.org"
source = f"https://cdn.kernel.org/pub/linux/kernel/v{pkgver[0]}.x/linux-{pkgver}.tar.xz"
sha256 = "7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83"
# no meaningful checking to be done
options = [
    "!ci",
    "!check",
    "!debug",
    "!strip",
    "!scanrundeps",
    "!scanshlibs",
    "!lto",
    "textrels",
    "execstack",
    "foreignelf",  # vdso32
]


def install(self):
    from cbuild.util import linux

    renv = dict(self.make_env)
    renv.update(self.make_install_env)
    linux.install(self, renv)
    for kdest in (self.destdir / "usr/lib/modules").glob("*-tiny"):
        # kernel sem modulos nao gera modules.order, mas os hooks de
        # kernel.d (run-kernel-d, 00-setup-kernels) exigem o arquivo
        # para gerenciar a versao (rsync p/ /boot etc.); vazio e suficiente
        (kdest / "apk-dist" / "modules.order").touch()
    self.install_file(
        self.files_path / "55-tiny-uki.sh", "usr/lib/kernel.d", mode=0o755
    )


@subpackage("linux-tiny-devel")
def _(self):
    self.options = ["foreignelf", "execstack", "!scanshlibs"]
    return ["usr/src", "usr/lib/modules/*/build"]
