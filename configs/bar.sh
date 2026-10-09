#!/bin/sh
# barra minima sem bard: esquerda data/hora, direita net/temp/mem/bat
while :; do
    dt=$(date '+%Y-%m-%d %H:%M')
    mem=$(awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} END{if(t) printf "%dMB",(t-a)/1024}' /proc/meminfo)
    net="down"
    for d in /sys/class/net/*; do
        n=$(basename "$d")
        [ "$n" = "lo" ] && continue
        [ "$(cat "$d/operstate" 2>/dev/null)" = "up" ] && { net="$n"; break; }
    done
    temp="n/a"
    for z in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp1_input; do
        [ -r "$z" ] || continue
        t=$(cat "$z")
        [ "$t" -gt 1000 ] && t=$((t/1000))
        temp="${t}C"
        break
    done
    bat=""
    for b in /sys/class/power_supply/BAT*/capacity; do
        [ -r "$b" ] && { bat=" BAT $(cat "$b")%"; break; }
    done
    printf '%%{l} %s %%{c} %%{r} %s %s %s%s \n' "$dt" "$net" "$temp" "$mem" "$bat"
    sleep 5
done | mojito -p -g 1920x28+0+0 -o 0 -B "#111316" -F "#96a4b2" -f monospace-10
