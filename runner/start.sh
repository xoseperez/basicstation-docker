#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Balena.io specific functions
# -----------------------------------------------------------------------------

function push_variables {
    if [[ "$BALENA_DEVICE_UUID" != "" ]]; then
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
   [[ "$BALENA_DEVICE_UUID" != "" ]] && balena-idle || exit 1
}

# -----------------------------------------------------------------------------
# Preparing configuration
# -----------------------------------------------------------------------------

# Move into configuration folder
mkdir -p config
pushd config >> /dev/null

# -----------------------------------------------------------------------------
# Mode (static/dynamic) & protocol (cups/lns)
# -----------------------------------------------------------------------------

# Configuration mode
if [[ -f ./station.conf ]]; then 
    MODE="STATIC"
    if [[ -f ./cups.key ]]; then
        PROTOCOL="CUPS"
    elif [[ -f ./tc.key ]]; then
        PROTOCOL="LNS"
    else
        echo -e "\033[91mERROR: Custom configuration folder found, but missing files: either cups.key or tc.key are required.\033[0m"
        idle
    fi
else
    MODE="DYNAMIC"
    if [[ "$CUPS_KEY" != "" ]]; then 
        PROTOCOL="CUPS"
    elif [[ "$TC_KEY" != "" ]]; then 
        PROTOCOL="LNS"
    else
        echo -e "\033[91mERROR: Missing configuration, either CUPS_KEY or TC_KEY are required.\033[0m"
        idle
    fi
fi

# Defaults to TTN server v3, `eu1` region, use a custom CUPS_URI or TC_URI to change this
TTN_REGION=${TTN_REGION:-"eu1"}
CUPS_URI=${CUPS_URI:-"https://${TTN_REGION}.cloud.thethings.network:443"} 
TC_URI=${TC_URI:-"wss://${TTN_REGION}.cloud.thethings.network:8887"} 

# CUPS protocol
if [[ "$PROTOCOL" == "CUPS" ]]; then
    if [[ ! -f ./cups.uri ]]; then 
        echo "$CUPS_URI" > cups.uri
    fi
    if [[ ! -f ./cups.trust ]]; then 
        if [[ "$CUPS_TRUST" == "" ]]; then
            cp /app/cacert.pem cups.trust
        else
            CUPS_TRUST=$(echo $CUPS_TRUST | sed 's/\s//g' | sed 's/-----BEGINCERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' | sed 's/-----ENDCERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' | sed 's/\n+/\n/g')
            echo "$CUPS_TRUST" > cups.trust
        fi
    fi
    if [[ ! -f ./cups.key ]]; then 
	    echo "Authorization: Bearer $CUPS_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > cups.key
    fi
fi

# LNS protocol
if [[ "$PROTOCOL" == "LNS" ]]; then
    if [[ ! -f ./tc.uri ]]; then 
        echo "$TC_URI" > tc.uri
    fi
    if [[ ! -f ./tc.trust ]]; then 
        if [[ "$TC_TRUST" == "" ]]; then
            cp /app/cacert.pem tc.trust
        else
            TC_TRUST=$(echo $TC_TRUST | sed 's/\s//g' | sed 's/-----BEGINCERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' | sed 's/-----ENDCERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' | sed 's/\n+/\n/g')
            echo "$TC_TRUST" > tc.trust
        fi
    fi
    if [[ ! -f ./tc.key ]]; then 
	    echo "Authorization: Bearer $TC_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > tc.key
    fi
fi

# -----------------------------------------------------------------------------
# Gateway EUI
# -----------------------------------------------------------------------------

if [[ "$MODE" == "STATIC" ]]; then
    GATEWAY_EUI=$(cat /app/config/station.conf | jq '.station_conf.routerid' | sed 's/"//g')
else
    if [[ -z $GATEWAY_EUI ]]; then
        GATEWAY_EUI_NIC=${GATEWAY_EUI_NIC:-"eth0"}
        if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
            GATEWAY_EUI_NIC="eth0"
        fi
        if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
            GATEWAY_EUI_NIC="wlan0"
        fi
        if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
            GATEWAY_EUI_NIC="usb0"
        fi
        if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
            # Last chance: get the most used NIC based on received bytes
            GATEWAY_EUI_NIC=$(cat /proc/net/dev | tail -n+3 | sort -k2 -nr | head -n1 | cut -d ":" -f1 | sed 's/ //g')
        fi
        if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
            echo -e "\033[91mERROR: No network interface found. Cannot set gateway EUI.\033[0m"
        fi
        GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
    fi
fi
GATEWAY_EUI=${GATEWAY_EUI^^}

# -----------------------------------------------------------------------------
# Model / concentrator configuration
# -----------------------------------------------------------------------------
# MODEL can be:
# * A developing gateway (mostly by RAKwireless), example: RAK7248
# * A concentrator module (by RAKWireless, IMST, SeeedStudio,...), example: RAK5416
# * A concentrator chip (Semtech's naming), example: SX1303

if [[ -z ${MODEL} ]]; then
    echo -e "\033[91mERROR: MODEL variable not set.\033[0m"
	idle
fi
MODEL=${MODEL^^}
declare -A MODEL_MAP=(
    [RAK7243]=SX1301 [RAK7243C]=SX1301 [RAK7244]=SX1301 [RAK7244C]=SX1301 [RAK7248]=SX1302 [RAK7248C]=SX1302 [RAK7271]=SX1302 [RAK7371]=SX1303 
    [RAK831]=SX1301 [RAK833]=SX1301 [RAK2245]=SX1301 [RAK2247]=SX1301 [RAK2287]=SX1302 [RAK5146]=SX1303
    [IC880A]=SX1301 [WM1302]=SX1302 [R11E-LORA8]=SX1308 [R11E-LORA9]=SX1308
    [SX1301]=SX1301 [SX1302]=SX1302 [SX1303]=SX1303 [SX1308]=SX1308
)
CONCENTRATOR=${MODEL_MAP[$MODEL]}
if [[ "${CONCENTRATOR}" == "" ]]; then
    echo -e "\033[91mERROR: Unknown MODEL value ($MODEL). Valid values are: ${!MODEL_MAP[@]}\033[0m"
	idle
fi

# -----------------------------------------------------------------------------
# Device (port) configuration
# -----------------------------------------------------------------------------

# Default interface is SPI
INTERFACE=${INTERFACE:-"SPI"}

# Check port and interface
if [[ "${MODE}" == "STATIC" ]]; then
    DEVICE=$(cat /app/config/station.conf | jq '.[] | .device' | head -1 | sed 's/"//g')
else
    DEVICE=${DEVICE:-$LORAGW_SPI} # backwards compatibility
    if [[ "${INTERFACE}" == "SPI" ]]; then
        DEVICE=${DEVICE:-"/dev/spidev0.0"}
    else
        DEVICE=${DEVICE:-"/dev/ttyACM0"}
    fi
    if [[ ! -e $DEVICE ]]; then
        echo -e "\033[91mERROR: $DEVICE does not exist.\033[0m"
        idle
    fi
fi

# Concentrator design
if [[ "${CONCENTRATOR}" == "SX1308" ]] && [[ "${INTERFACE}" == "USB" ]]; then
    DESIGN=${DESIGN:-"picocell"}
elif [[ "${CONCENTRATOR}" == "SX1301" ]] || [[ "${CONCENTRATOR}" == "SX1308" ]]; then
    DESIGN=${DESIGN:-"v2"}
fi
DESIGN=${DESIGN:-"corecell"}
DESIGN=${DESIGN,,}

# USB interface is not available for SX1301 concentrators
if [[ "${CONCENTRATOR}" == "SX1301" ]] && [[ "$INTERFACE" == "USB" ]]; then
    echo -e "\033[91mERROR: USB interface is not available for SX1301 concentrators.\033[0m"
	idle
fi

# Set default SPI speed for SX1301 concentrators to 2MHz
if [[ "${CONCENTRATOR}" == "SX1301" ]]; then
    SPI_SPEED=${SPI_SPEED:-2000000}
fi
export LORAGW_SPI_SPEED=${SPI_SPEED:-8000000}

# -----------------------------------------------------------------------------
# GPIO configuration (reset and power enable), only for SPI concentrators
# -----------------------------------------------------------------------------

# Map hardware pins to GPIO on Raspberry Pi
declare -a GPIO_MAP=( -1 -1 -1 2 -1 3 -1 4 14 -1 15 17 18 27 -1 22 23 -1 24 10 -1 9 25 11 8 -1 7 0 1 5 -1 6 12 13 -1 19 16 26 20 -1 21 )
GW_RESET_PIN=${GW_RESET_PIN:-11}
GW_RESET_GPIO=${GW_RESET_GPIO:-${GPIO_MAP[$GW_RESET_PIN]}}

# Some board might have an enable GPIO
GW_POWER_EN_GPIO=${GW_POWER_EN_GPIO:-0}
GW_POWER_EN_LOGIC=${GW_POWER_EN_LOGIC:-1}

# -----------------------------------------------------------------------------
# Debug
# -----------------------------------------------------------------------------

echo ""
echo "------------------------------------------------------------------"
echo "Protocol"
echo "------------------------------------------------------------------"
echo "Mode:          $MODE"
echo "Protocol:      $PROTOCOL"
if [[ "$PROTOCOL" == "CUPS" ]]; then
echo "CUPS Server:   $CUPS_URI"
else
echo "LNS Server:    $TC_URI"
fi
if [[ ! -z $GATEWAY_EUI_NIC ]]; then
echo "Main NIC:      $GATEWAY_EUI_NIC"
fi
echo "Gateway EUI:   $GATEWAY_EUI"
echo "------------------------------------------------------------------"
echo "Radio"
echo "------------------------------------------------------------------"
echo "Model:         $MODEL"
echo "Concentrator:  $CONCENTRATOR"
echo "Design:        ${DESIGN^^}"
echo "Radio Device:  $DEVICE"
echo "Interface:     $INTERFACE"
if [[ "$INTERFACE" == "SPI" ]]; then
echo "SPI Speed:     $LORAGW_SPI_SPEED"
fi
echo "Reset GPIO:    $GW_RESET_GPIO"
echo "Enable GPIO:   $GW_POWER_EN_GPIO"
if [[ $GW_POWER_EN_GPIO -ne 0 ]]; then
echo "Enable Logic:  $GW_POWER_EN_LOGIC"
fi
echo "------------------------------------------------------------------"
echo ""

# Push variables to Balena
push_variables

# -----------------------------------------------------------------------------
# Generate dynamic configuration files
# -----------------------------------------------------------------------------

# Link the corresponding configuration file
if [[ ! -f ./station.conf ]]; then
    cp /app/station.${DESIGN}.conf station.conf
    sed -i "s#\"device\":\s*.*,#\"device\": \"${INTERFACE,,}:${DEVICE}\",#" station.conf
    sed -i "s#\"routerid\":\s*.*,#\"routerid\": \"$GATEWAY_EUI\",#" station.conf
fi

# If stdn variant (or any *n variant) we need at least one slave concentrator
if [[ ! -f ./slave-0.conf ]]; then
    echo "{}" > slave-0.conf
fi

# -----------------------------------------------------------------------------
# Start basicstation
# -----------------------------------------------------------------------------

# Reset the concentrator
RESET_GPIO=$GW_RESET_GPIO POWER_EN_GPIO=$GW_POWER_EN_GPIO POWER_EN_LOGIC=$GW_POWER_EN_LOGIC /app/reset.sh

# Execute packet forwarder
/app/design-${DESIGN}/bin/station -f
