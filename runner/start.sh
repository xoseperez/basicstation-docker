#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------

COLOR_INFO="\e[32m" # green
COLOR_WARNING="\e[33m" # yellow
COLOR_ERROR="\e[31m" # red
COLOR_END="\e[0m"

# -----------------------------------------------------------------------------
# Balena.io specific functions
# -----------------------------------------------------------------------------

# Load Balena methods
if [ "$BALENA_DEVICE_UUID" != "" ]; then
    source ./balena.sh
fi

function idle() {
    echo -e "${COLOR_INFO}GATEWAY_EUI: ${GATEWAY_EUI}${COLOR_END}"
   [[ "$BALENA_DEVICE_UUID" != "" ]] && balena-idle || exit 1
}

# -----------------------------------------------------------------------------
# Preparing configuration
# -----------------------------------------------------------------------------

# Move into configuration folder
mkdir -p config
pushd config >> /dev/null

# -----------------------------------------------------------------------------
# Gateway EUI
# -----------------------------------------------------------------------------

if [[ -f ./station.conf ]]; then
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
            echo -e "${COLOR_ERROR}ERROR: No network interface found. Cannot set gateway EUI.${COLOR_END}"
        fi
        GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
    fi
fi
GATEWAY_EUI=${GATEWAY_EUI^^}

# Push to Balena
balena_set_label "EUI" "$GATEWAY_EUI"

# -----------------------------------------------------------------------------
# Mode (static/dynamic) & protocol (cups/lns)
# -----------------------------------------------------------------------------

# New USE_CUPS variable, will be mandatory in the future
# Possible values are 0 or 1, setting it here to 2 when undefined
USE_CUPS=${USE_CUPS:-2} # undefined by default

# Configuration mode
if [[ -f ./station.conf ]]; then 
    MODE="STATIC"
    if [[ $USE_CUPS -eq 1 ]]; then
        PROTOCOL="CUPS"
    elif [[ -f ./cups.key ]] && [[ $USE_CUPS -ne 0 ]]; then
        PROTOCOL="CUPS"
        echo -e "${COLOR_WARNING}WARNING: USE_CUPS variable will be mandatory in future versions to enable CUPS.${COLOR_END}"
    elif [[ -f ./tc.key ]]; then
        PROTOCOL="LNS"
    else
        echo -e "${COLOR_ERROR}ERROR: Custom configuration folder found, but missing files: either force key-less CUPS with USE_CUPS=1 or provide a cups.key or tc.key files.${COLOR_END}"
        idle
    fi
else
    MODE="DYNAMIC"
    if [[ $USE_CUPS -eq 1 ]]; then
        PROTOCOL="CUPS"
    elif [[ "$CUPS_KEY" != "" ]] && [[ $USE_CUPS -ne 0 ]]; then
        PROTOCOL="CUPS"
        echo -e "${COLOR_WARNING}WARNING: USE_CUPS variable will be mandatory in future versions to enable CUPS.${COLOR_END}"
    elif [[ "$TC_KEY" != "" ]]; then 
        PROTOCOL="LNS"
    else
        echo -e "${COLOR_ERROR}ERROR: Missing configuration, either force key-less CUPS with USE_CUPS=1 or define CUPS_KEY or TC_KEY.${COLOR_END}"
        idle
    fi
fi

# -----------------------------------------------------------------------------
# LNS/CUPS configuration
# -----------------------------------------------------------------------------

# Defaults to TTN server v3, `eu1` region, use a custom CUPS_URI or TC_URI to change this
TTN_REGION=${TTN_REGION:-"eu1"}
CUPS_URI=${CUPS_URI:-"https://${TTN_REGION}.cloud.thethings.network:443"} 
TC_URI=${TC_URI:-"wss://${TTN_REGION}.cloud.thethings.network:8887"} 
TC_URL=$TC_URI

# Autoprovision variables needed
TC_AUTOPROVISION=${TC_AUTOPROVISION:-"N"} 
TC_USERNAME=${TC_USERNAME:-"none"}
TC_AUTOPROVISION_URI=${TC_AUTOPROVISION_URI:-"company-region-plus-url"} #For TTN: eu1.cloud.thethings.network // For TTI: your-company.eu1.thethings.industries
TC_AUTHORIZATION=${TC_AUTHORIZATION:-"your-personal-api-key"} 
TC_AUTOPROVISION_REGION=${TC_AUTOPROVISION_REGION:-"EU_863_870_TTN"} #ToDo: find the list!
GATEWAY_NAME=${GATEWAY_NAME:-"gateway-name"}
GATEWAY_ID=${GATEWAY_ID:-"gateway-id"}


# Autoprovision
if [[ "$TC_AUTOPROVISION" == "Y" ]]; then

    CODE=$(curl --location \
            --header 'Accept: application/json' \
            --header 'Authorization: Bearer '$TC_AUTHORIZATION'' \
            --header 'Content-Type: application/json' \
            --request POST \
            --data-raw '{
                "gateway": {
                "ids": {
                    "gateway_id": "'$GATEWAY_ID'",
                    "eui": "'$GATEWAY_EUI'"
                },
                "name": "'$GATEWAY_NAME'",
                "gateway_server_address": "'$TC_AUTOPROVISION_URI'",
                "frequency_plan_id": "'$TC_AUTOPROVISION_REGION'"
                }
            }' \
            'https://'$TC_AUTOPROVISION_URI'/api/v3/users/'$TC_USERNAME'/gateways' | jq --raw-output '.code')
    
    # ToDo: find more error codes when provision a gateway via API.   
    if [[ -z "$CODE" ]]; then
        echo "No errors autoprovisioning the gateway!"
    elif [[ "$CODE" == 6 ]]; then
        echo -e "\033[91mERROR: The gateway EU $GATEWAY_EUI is already registered (by you or someone else). Delete the gateway or change the Device Variable TC_AUTOPROVISION to 'N'."
        idle
    elif [[ "$CODE" == 9 ]]; then
        echo -e "\033[91mERROR: The gateway had already been autoprovisioned. Error $CODE. Change the GATEWAY_NAME and GATEWAY_ID or change the Device Variable TC_AUTOPROVISION to 'N'."
        #idle
    else
        echo -e "\033[91mERROR: The gateway had an error when autoprovisioned $CODE."
        #idle
    fi


    API_KEY=$(curl --location \
        --header 'Accept: application/json' \
        --header 'Authorization: Bearer '$TC_AUTHORIZATION'' \
        --header 'Content-Type: application/json' \
        --request POST \
        --data-raw '{
            "name":"balena-key",
            "rights":["RIGHT_GATEWAY_LINK"],
            "expires_at":null
        }' \
        'https://'$TC_AUTOPROVISION_URI'/api/v3/gateways/'$GATEWAY_ID'/api-keys' | jq --raw-output '.key')

    TC_KEY=$API_KEY
    TC_URI="wss://${TC_AUTOPROVISION_URI}:8887"

    # Push TC_KEY to balena
    balena_set_variable "TC_KEY" "$TC_KEY"

fi


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
# Model / concentrator configuration
# -----------------------------------------------------------------------------
# MODEL can be:
# * A developing gateway (mostly by RAKwireless), example: RAK7248
# * A concentrator module (by RAKWireless, IMST, SeeedStudio,...), example: RAK5416
# * A concentrator chip (Semtech's naming), example: SX1303

if [[ -z ${MODEL} ]]; then
    echo -e "${COLOR_ERROR}ERROR: MODEL variable not set.${COLOR_END}"
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
    echo -e "${COLOR_ERROR}ERROR: Unknown MODEL value ($MODEL). Valid values are: ${!MODEL_MAP[@]}${COLOR_END}"
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
        echo -e "${COLOR_ERROR}ERROR: $DEVICE does not exist.${COLOR_END}"
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
    echo -e "${COLOR_ERROR}ERROR: USB interface is not available for SX1301 concentrators.${COLOR_END}"
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

# Default RESET pin (by their position on the 40-pin header)
if [ "${INTERFACE}" == "USB" ]; then
    GW_RESET_PIN=${GW_RESET_PIN:-0}
else
    GW_RESET_PIN=${GW_RESET_PIN:-11}
fi

# Map hardware pins to GPIO on Raspberry Pi
declare -a GPIO_MAP=( 0 0 0 2 0 3 0 4 14 0 15 17 18 27 0 22 23 0 24 10 0 9 25 11 8 0 7 0 1 5 0 6 12 13 0 19 16 26 20 0 21 )
GW_RESET_GPIO=${GW_RESET_GPIO:-${GPIO_MAP[$GW_RESET_PIN]}}

# Some board might have an enable GPIO
GW_POWER_EN_GPIO=${GW_POWER_EN_GPIO:-0}
GW_POWER_EN_LOGIC=${GW_POWER_EN_LOGIC:-1}

# -----------------------------------------------------------------------------
# Debug
# -----------------------------------------------------------------------------

echo -e "${COLOR_INFO}------------------------------------------------------------------${COLOR_END}"
echo -e "${COLOR_INFO}Protocol${COLOR_END}"
echo -e "${COLOR_INFO}------------------------------------------------------------------${COLOR_END}"
echo -e "${COLOR_INFO}Mode:          ${MODE}${COLOR_END}"
echo -e "${COLOR_INFO}Protocol:      ${PROTOCOL}${COLOR_END}"
if [[ "$PROTOCOL" == "CUPS" ]]; then
echo -e "${COLOR_INFO}CUPS Server:   ${CUPS_URI}${COLOR_END}"
else
echo -e "${COLOR_INFO}LNS Server:    ${TC_URI}${COLOR_END}"
fi
if [[ ! -z $GATEWAY_EUI_NIC ]]; then
echo -e "${COLOR_INFO}Main NIC:      ${GATEWAY_EUI_NIC}${COLOR_END}"
fi
echo -e "${COLOR_INFO}Gateway EUI:   ${GATEWAY_EUI}${COLOR_END}"
echo -e "${COLOR_INFO}------------------------------------------------------------------${COLOR_END}"
echo -e "${COLOR_INFO}Radio${COLOR_END}"
echo -e "${COLOR_INFO}------------------------------------------------------------------${COLOR_END}"
echo -e "${COLOR_INFO}Model:         ${MODEL}${COLOR_END}"
echo -e "${COLOR_INFO}Concentrator:  ${CONCENTRATOR}${COLOR_END}"
echo -e "${COLOR_INFO}Design:        ${DESIGN^^}${COLOR_END}"
echo -e "${COLOR_INFO}Radio Device:  ${DEVICE}${COLOR_END}"
echo -e "${COLOR_INFO}Interface:     ${INTERFACE}${COLOR_END}"
if [[ "$INTERFACE" == "SPI" ]]; then
echo -e "${COLOR_INFO}SPI Speed:     ${LORAGW_SPI_SPEED}${COLOR_END}"
fi
echo -e "${COLOR_INFO}Reset GPIO:    ${GW_RESET_GPIO}${COLOR_END}"
echo -e "${COLOR_INFO}Enable GPIO:   ${GW_POWER_EN_GPIO}${COLOR_END}"
if [[ $GW_POWER_EN_GPIO -ne 0 ]]; then
echo -e "${COLOR_INFO}Enable Logic:  ${GW_POWER_EN_LOGIC}${COLOR_END}"
fi
echo -e "${COLOR_INFO}------------------------------------------------------------------${COLOR_END}"

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
# Create reset file
# -----------------------------------------------------------------------------

cp /app/reset.sh.template reset.sh
sed -i "s#{{RESET_GPIO}}#${RESET_GPIO:-17}#" reset.sh
sed -i "s#{{POWER_EN_GPIO}}#${POWER_EN_GPIO:-0}#" reset.sh
sed -i "s#{{POWER_EN_LOGIC}}#${POWER_EN_LOGIC:-1}#" reset.sh
chmod +x reset.sh

# -----------------------------------------------------------------------------
# Start basicstation
# -----------------------------------------------------------------------------

# Execute packet forwarder
STATION_RADIOINIT=./reset.sh /app/design-${DESIGN}/bin/station -f
