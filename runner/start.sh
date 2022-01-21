#!/usr/bin/env bash

function push_variables {
    if [ "$BALENA_DEVICE_UUID" != "" ]
    then

        ID=$(curl -sX GET "https://api.balena-cloud.com/v5/device?\$filter=uuid%20eq%20'$BALENA_DEVICE_UUID'" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" | \
            jq ".d | .[0] | .id")

        TAG=$(curl -sX POST \
            "https://api.balena-cloud.com/v5/device_tag" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" \
            --data "{ \"device\": \"$ID\", \"tag_key\": \"EUI\", \"value\": \"$GATEWAY_EUI\" }" > /dev/null)

    fi
}

function idle {
   [ "$BALENA_DEVICE_UUID" != "" ] && balena-idle || exit 1
}

# Retrieve the concentrator
if [ -z ${MODEL} ] ;
then
    echo -e "\033[91mERROR: MODEL variable not set.\nSet the model of the gateway you are using (SX1301, SX1302 or SX1303).\033[0m"
	idle
fi
MODEL=${MODEL^^}
declare -A MODEL_MAP=(
    [SX1301]=sx1301 [RAK831]=sx1301 [RAK833]=sx1301 [RAK2245]=sx1301 [RAK2247]=sx1301 [IC880A]=sx1301
    [SX1302]=sx1302 [RAK2287]=sx1302 [WM1302]=sx1302
    [SX1303]=sx1302 [RAK5146]=sx1302
)
CONCENTRATOR=${MODEL_MAP[$MODEL]}
if [ "${CONCENTRATOR}" == "" ] ;
then
    echo -e "\033[91mERROR: Unknown MODEL value ($MODEL).\033[0m"
	idle
fi

# Check if SPI port exists
LORAGW_SPI=${LORAGW_SPI:-"/dev/spidev0.0"}
if [ ! -e $LORAGW_SPI ]
then
    echo -e "\033[91mERROR: $LORAGW_SPI does not exist. Is SPI enabled?\033[0m"
	idle
fi

# Map hardware pins to GPIO on Raspberry Pi
declare -a GPIO_MAP=( -1 -1 -1 2 -1 3 -1 4 14 -1 15 17 18 27 -1 22 23 -1 24 10 -1 9 25 11 8 -1 7 0 1 5 -1 6 12 13 -1 19 16 26 20 -1 21 )
GW_RESET_PIN=${GW_RESET_PIN:-11}
GW_RESET_GPIO=${GW_RESET_GPIO:-${GPIO_MAP[$GW_RESET_PIN]}}

# Some board might have an enable GPIO
GW_POWER_EN_GPIO=${GW_POWER_EN_GPIO:-0}

# Get the Gateway EUI
GATEWAY_EUI=$(cat /sys/class/net/eth0/address | sed -r 's/[:]+//g' | sed -e 's#\(.\{6\}\)\(.*\)#\1fffe\2#g')
GATEWAY_EUI=${GATEWAY_EUI^^}

# Defaults to TTN server v3, EU1 region, use a custom TC_URI to change this
TTN_REGION=${TTN_REGION:-"eu1"}
TC_URI=${TC_URI:-"wss://${TTN_REGION}.cloud.thethings.network:8887"} 

# Get certificate
TC_TRUST=${TC_TRUST:-$(curl --silent "https://letsencrypt.org/certs/{trustid-x3-root.pem.txt,isrgrootx1.pem}")}

# Sanitize TC_TRUST
TC_TRUST=$(echo $TC_TRUST | sed 's/\s//g' | sed 's/-----BEGINCERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' | sed 's/-----ENDCERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' | sed 's/\n+/\n/g')

# Check configuration
if [ "$TC_URI" == "" ] || [ "$TC_TRUST" == "" ]
then
    echo -e "\033[91mERROR: Missing configuration, define TC_URI and TC_TRUST.\033[0m"
	idle
fi

# Debug
echo "------------------------------------------------------------------"
echo "Model:       $MODEL"
echo "Gateway EUI: $GATEWAY_EUI"
echo "Reset GPIO:  $GW_RESET_GPIO"
echo "Enable GPIO: $GW_POWER_EN_GPIO"
echo "Device:      $LORAGW_SPI"
echo "Server:      $TC_URI"
echo "------------------------------------------------------------------"

# Push variables to Balena
push_variables

# Setup TC files from environment
echo "$TC_URI" > tc.uri
echo "$TC_TRUST" > tc.trust
if [ ! -z ${TC_KEY} ]; then
	echo "Authorization: Bearer $TC_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > tc.key
fi

# Export variables used by other scripts
export GW_RESET_GPIO=$GW_RESET_GPIO
export GW_POWER_EN_GPIO=$GW_POWER_EN_GPIO

# Link the corresponding configuration file and run station
ln station.${CONCENTRATOR}.conf station.conf
STATION_RADIOINIT=./reset.sh RADIODEV=$LORAGW_SPI ${CONCENTRATOR}/bin/station -f
