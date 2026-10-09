#!/bin/sh
# rede estatica (substitui dhcpcd): enp1s0 192.168.122.187/24 via 192.168.122.1
ip link set enp1s0 up
ip addr replace 192.168.122.187/24 dev enp1s0
ip route replace default via 192.168.122.1 dev enp1s0 proto static metric 100
exit 0
