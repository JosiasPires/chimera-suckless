#!/bin/sh
# 55-tiny-uki: rebuild the Unified Kernel Image for *-tiny kernels and
# refresh the Chimera-UKI efiboot entry.
#
# Runs after 50-initramfs (numbered 55), so /boot/initrd.img-<ver> exists.
# Requires the one-line kernel command line in /etc/kernel/cmdline-tiny
# (created by chimera-suckless install.sh from the running system).
#
# The UKI filename is stable (chimera-tiny.efi), so kernel upgrades keep
# working even if the efiboot entry were stale; the entry refresh keeps
# BootOrder position.

LABEL="Chimera-UKI"
UKI_NAME="chimera-tiny.efi"
CMDLINE_FILE="/etc/kernel/cmdline-tiny"
KRET=0

[ -d /sys/firmware/efi ] || exit 0
command -v ukify >/dev/null 2>&1 || exit 0
command -v efibootmgr >/dev/null 2>&1 || exit 0
command -v linux-version >/dev/null 2>&1 || exit 0

if [ ! -f "$CMDLINE_FILE" ]; then
    echo "55-tiny-uki: $CMDLINE_FILE missing, skipping (see GUIDE.md)"
    exit 0
fi

# ESP: /boot is the ESP on the chimera-suckless layout; fall back to /efi
ESP=""
for cand in /boot /efi; do
    if [ "$(findmnt -no FSTYPE -T "$cand" 2>/dev/null)" = "vfat" ]; then
        ESP="$cand"
        break
    fi
done
if [ -z "$ESP" ]; then
    echo "55-tiny-uki: no vfat ESP at /boot or /efi, skipping"
    exit 0
fi
UKIDIR="$ESP/EFI/Linux"
mkdir -p "$UKIDIR" || exit 1

for KVER in $(linux-version list 2>/dev/null | linux-version sort --reverse); do
    case "$KVER" in
        *-tiny) ;;
        *) continue ;;
    esac
    VMLINUZ="/boot/vmlinuz-${KVER}"
    INITRD="/boot/initrd.img-${KVER}"
    [ -f "$VMLINUZ" ] || continue
    [ -f "$INITRD" ] || continue
    # um unico UKI (nome estavel): a versao tiny mais nova vence.
    # carimbo de versao ao lado do UKI: mtime nao serve (vmlinuz empacotado
    # carrega mtime do build, sempre mais velho que um UKI ja gerado).
    UKI="$UKIDIR/$UKI_NAME"
    STAMP="$UKIDIR/.chimera-tiny.version"
    # rebuild quando: sem UKI, versao nova, ou entradas mais novas que o UKI
    # (ex: initrd regenerado localmente tem mtime fresco e conta aqui)
    if [ -f "$UKI" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$KVER" ] \
        && [ "$UKI" -nt "$VMLINUZ" ] && [ "$UKI" -nt "$INITRD" ]; then
        break
    fi
    echo "55-tiny-uki: building $UKI for $KVER..."
    if ! ukify build --linux="$VMLINUZ" --initrd="$INITRD" \
        --cmdline="@$CMDLINE_FILE" --output="$UKI"; then
        echo "55-tiny-uki: ukify FAILED for $KVER"
        KRET=1
        break
    fi
    echo "$KVER" > "$STAMP"
    # refresh the efiboot entry, preserving BootOrder position
    ESPSRC=$(findmnt -no SOURCE -T "$UKIDIR")
    case "$ESPSRC" in
        *[0-9]p[0-9]*)
            DISK=${ESPSRC%p*}
            PART=${ESPSRC##*p}
            ;;
        *)
            DISK=$(echo "$ESPSRC" | sed 's/[0-9]*$//')
            PART=$(echo "$ESPSRC" | sed 's/^.*[^0-9]\([0-9]*\)$/\1/')
            ;;
    esac
    OLDORDER=$(efibootmgr | sed -n 's/^BootOrder: //p')
    OLDNUMS=$(efibootmgr | sed -n "s/^Boot\([0-9A-Fa-f]*\)\* $LABEL.*/\1/p")
    for old in $OLDNUMS; do
        efibootmgr -b "$old" -B >/dev/null 2>&1 || true
    done
    if ! efibootmgr -c -d "$DISK" -p "$PART" -L "$LABEL" \
        -l "\\EFI\\Linux\\$UKI_NAME" >/dev/null 2>&1; then
        echo "55-tiny-uki: efibootmgr FAILED"
        KRET=1
        break
    fi
    NEWNUM=$(efibootmgr | sed -n "s/^Boot\([0-9A-Fa-f]*\)\* $LABEL.*/\1/p" | head -1)
    if [ -n "$NEWNUM" ] && [ -n "$OLDORDER" ]; then
        # tiny e primario por desegno: UKI primeiro, resto dedupado atras.
        # (generico continua na ordem como fallback.)
        NEWORDER="$NEWNUM"
        for old in $(echo "$OLDORDER" | tr ',' ' '); do
            case ",$NEWORDER," in *",$old,"*) ;; *) NEWORDER="$NEWORDER,$old";; esac
        done
        efibootmgr -o "$NEWORDER" >/dev/null 2>&1 || true
    fi
    echo "55-tiny-uki: $LABEL entry updated ($ESPSRC)."
    break
done

exit $KRET
