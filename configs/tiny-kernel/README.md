# Kernel tiny (`tiny-kernel/`)

- `config-tiny` — `.config` real usado no build validado (Linux 7.2.2,
  `LOCALVERSION=-tiny`, tudo builtin, zero módulos). Ponto de partida para
  `files/config-x86_64.tiny` no template cports `linux-tiny`.
- Estratégia dual-kernel (decidida): **GARANTIDO** = kernel compilado por nós
  mesmos e validado no boot (fallback permanente); **PRIMÁRIO** = build do
  GitHub Actions, mais recente (_FAILURES voltam sozinhas para o garantido
  via ordem do BootOrder_ + entry genérica de rescue).

## Símbolos mandatórios (extraídos no sangue — cada um custou um ciclo rescue)

Sem estes, initramfs/dinit/pipewire quebram de formas crípticas:

```
64BIT (tinyconfig default é 32-bit! firmware x64 rejeita com "Unsupported")
EFI_STUB, RELOCATABLE, EFIVAR_FS
BLOCK, BLK_DEV (tinyconfig desliga a camada de bloco!)
BINFMT_ELF, BINFMT_SCRIPT, BINFMT_MISC
FILE_LOCKING (cryptsetup morre sem)
CGROUPS + controllers (SCHED/MEMCG(+SWAP)/BLK_CGROUP(+IOCOST)/PIDS/DEVICE/MISC/BPF)
  — cgroup.controllers vazio + set -e do cgroups.sh = boot inteiro em cascata
MULTIUSER (p/ SECURITY→YAMA), SYSVIPC (p/ IPC_NS), POSIX_MQUEUE
NAMESPACES + UTS/IPC/PID/NET (+CGROUP_NS se precisar)
FUTEX + FUTEX_PI (pipewire morre com ENOSYS sem)
MEMFD_CREATE, EVENTFD, AIO
INOTIFY_USER, SIGNALFD, TIMERFD, EPOLL
KEXEC(+FILE), SECURITY+YAMA, COREDUMP (helper sysctl do dinit reclama sem)
VIRTIO* (BLK/NET/CONSOLE/BALLOON/PCI/MENU), DRM_VIRTIO_GPU (+SHMEM/KMS/FBDEV),
FB_EFI/VESA, FRAMEBUFFER_CONSOLE, VT(+CONSOLE), VGA/DUMMY_CONSOLE
INPUT(+KEYBOARD/EVDEV), ATKBD, SERIO_I8042
EXT4, VFAT (+NLS 437/8859-1), TMPFS/PROC/SYSFS, DEVTMPFS(+MOUNT)
BLK_DEV_INITRD, RD_GZIP/XZ/ZSTD, BLK_DEV_DM, DM_CRYPT, EFI/MSDOS_PARTITION
CRYPTO(+AES(NI)/XTS/SHA256/ZSTD), NET/INET/IPV6/PACKET/UNIX, BPF_SYSCALL
RTC_CLASS/HCTOSYS/CMOS, ACPI(+BUTTON), SERIAL_8250(+CONSOLE)
HW_RANDOM(+VIRTIO), TTY, UNIX98_PTYS, PRINTK, SWAP, ZRAM, ZSMALLOC
MTRR, X86_PAT, KVM_GUEST, PARAVIRT(+SPINLOCKS), HYPERVISOR_GUEST
SMP, CGROUPS, SECCOMP, MODULES (pode ficar =y mesmo sem =m p/ initramfs-tools)
SND(+TIMER/PCM/HWDEP/SEQ/RAWMIDI/JACK/HDA_INTEL/codecs generics) — só se quiser áudio
MAGIC_SYSRQ (debug via HMP sendkey; opcional no final)
```

Regras de bolso: após cada `scripts/config`, rode `make olddefconfig` e
**re-confira com `grep CONFIG_X=y`** — ele derruba símbolos com dependência
não atendida sem avisar. Cheque `/usr/lib/kernel.d/` + `update-initramfs`
após instalar; `sync` + `sha256sum` origem×destino antes de qualquer reboot
forçado (`virsh destroy` sem sync já nos queimou uma vez).
