#!/bin/sh
# inicia bswc; so sobe wallpaper e barra DEPOIS que o socket wayland existir
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
fi
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
swc-launch bswc &
n=0
SOCK=""
while [ $n -lt 100 ]; do
    SOCK=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -n 1)
    if [ -S "$SOCK" ]; then
        break
    fi
    sleep 0.2
    n=$((n + 1))
done
if [ -S "$SOCK" ]; then
    export WAYLAND_DISPLAY=$(basename "$SOCK")
    wawa fill "$HOME/Pictures/wallpaper.jpg" &
    sleep 0.5
    "$HOME/bin/bar.sh" &
else
    echo "start-bswc: wayland socket nao apareceu" >&2
fi
wait
