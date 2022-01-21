#!/usr/bin/env bash 

# Get the Gateway EUI
GATEWAY_EUI=$(cat /sys/class/net/eth0/address | sed -r 's/[:]+//g' | sed -e 's#\(.\{6\}\)\(.*\)#\1fffe\2#g')
GATEWAY_EUI=${GATEWAY_EUI^^}
echo $GATEWAY_EUI
