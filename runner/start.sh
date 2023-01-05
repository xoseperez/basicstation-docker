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

function restart_if_balena() {
   [[ "$BALENA_DEVICE_UUID" != "" ]] && \
   echo -e "${COLOR_INFO}Service will restart now${COLOR_END}" && \
   balena-idle
}

# -----------------------------------------------------------------------------
# TTI autoprovision gateway
# -----------------------------------------------------------------------------

function tts_autoprovision() {

    echo "Gateway provisioning using provided TTS_PERSONAL_KEY"

    # Autoprovision variables needed
    TTS_USERNAME=${TTS_USERNAME:-"none"}
    GATEWAY_PREFIX=${GATEWAY_PREFIX:-"eui"}
    GATEWAY_ID=${GATEWAY_ID:-"${GATEWAY_PREFIX,,}-${GATEWAY_EUI,,}"}
    GATEWAY_NAME=${GATEWAY_NAME:-${GATEWAY_ID}}
    
    # Autoprovision regions defined here: https://www.thethingsindustries.com/docs/reference/frequency-plans/
    TTS_FREQUENCY_PLAN_ID=${TTS_FREQUENCY_PLAN_ID:-""}
    if [[ "$TTS_FREQUENCY_PLAN_ID" == "" ]]; then
        if [[ "$TTS_REGION" == "nam1" ]]; then
            TTS_FREQUENCY_PLAN_ID="US_902_928_FSB_2"
        elif [[ "$TTS_REGION" == "au1" ]]; then
            TTS_FREQUENCY_PLAN_ID="AU_915_928_FSB_2"
        else
            TTS_FREQUENCY_PLAN_ID="EU_863_870_TTN"
        fi
    fi

    local API_KEY_NAME="autoprovision-lns-key"
    local RAW

    RAW=$(curl -s --location \
        --header 'Accept: application/json' \
        --header 'Authorization: Bearer '$TTS_PERSONAL_KEY'' \
        --header 'Content-Type: application/json' \
        --request POST \
        --data-raw '{
            "gateway": {
            "ids": {
                "gateway_id": "'$GATEWAY_ID'",
                "eui": "'$GATEWAY_EUI'"
            },
            "name": "'$GATEWAY_NAME'",
            "gateway_server_address": "'$SERVER'",
            "frequency_plan_id": "'$TTS_FREQUENCY_PLAN_ID'"
            }
        }' \
        'https://'$SERVER'/api/v3/users/'$TTS_USERNAME'/gateways' 2>/dev/null)
    
    #echo $RAW | jq
    local CODE=$(echo $RAW | jq --raw-output '.code' 2>/dev/null)
    local MESSAGE=$(echo $RAW | jq --raw-output '.message_format' 2>/dev/null)

    # ToDo: find more error codes when provision a gateway via API.   
    if [[ "$CODE" == "null" ]]; then
        echo "No errors autoprovisioning the gateway!"
    elif [[ "$CODE" == 6 ]]; then
        echo -e "${COLOR_WARNING}WARNING: The gateway $GATEWAY_ID is already registered (by you or someone else)${COLOR_END}"
        #idle
    elif [[ "$CODE" == 9 ]]; then
        echo -e "${COLOR_WARNING}WARNING: The gateway had already been autoprovisioned${COLOR_END}"
        #idle
    else
        echo -e "${COLOR_ERROR}ERROR: The gateway had an error when autoprovisioned: $MESSAGE ($CODE)${COLOR_END}\n"
        idle
    fi

    # List api keys
    local IDS=$(curl -s --location \
        --header 'Accept: application/json' \
        --header 'Authorization: Bearer '$TTS_PERSONAL_KEY'' \
        --header 'Content-Type: application/json' \
        --request GET \
        'https://'$SERVER'/api/v3/gateways/'$GATEWAY_ID'/api-keys' | jq '.api_keys[] | select(.name == "'$API_KEY_NAME'") | .id' 2>/dev/null)
    
    # Delete previous API keys
    for ID in ${IDS[@]}; do
        ID=$(echo $ID | tr -d '"')
        curl -s --location \
            --header 'Accept: application/json' \
            --header 'Authorization: Bearer '$TTS_PERSONAL_KEY'' \
            --header 'Content-Type: application/json' \
            --request PUT \
            --data-raw '{
                "name":"'$API_KEY_NAME'",
                "rights":[],
                "expires_at":null
            }' \
            'https://'$SERVER'/api/v3/gateways/'$GATEWAY_ID'/api-keys/'$ID >/dev/null
    done

    # Create new api key
    RAW=$(curl -s --location \
        --header 'Accept: application/json' \
        --header 'Authorization: Bearer '$TTS_PERSONAL_KEY'' \
        --header 'Content-Type: application/json' \
        --request POST \
        --data-raw '{
            "name":"'$API_KEY_NAME'",
            "rights":["RIGHT_GATEWAY_LINK"],
            "expires_at":null
        }' \
        'https://'$SERVER'/api/v3/gateways/'$GATEWAY_ID'/api-keys' 2>/dev/null)

    #echo $RAW | jq
    local KEY=$(echo $RAW | jq --raw-output '.key' 2>/dev/null)

    if [[ "$KEY" != "null" ]]; then
        TC_KEY=$KEY
        echo "TC_KEY successfully generated"
        [[ "$BALENA_DEVICE_UUID" != "" ]] && balena_set_variable "TC_KEY" "$TC_KEY"
        restart_if_balena
    fi

}

# -----------------------------------------------------------------------------
# Utils
# -----------------------------------------------------------------------------

function clean_certs_keys() {
    echo $1 | sed 's/\s//g' | \
        sed 's/-----BEGINCERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' | \
        sed 's/-----ENDCERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' | \
        sed 's/-----BEGINPRIVATEKEY-----/-----BEGIN PRIVATE KEY-----\n/g' | \
        sed 's/-----ENDPRIVATEKEY-----/\n-----END PRIVATE KEY-----\n/g' | \
        sed 's/\n+/\n/g'
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
            echo -e "${COLOR_ERROR}ERROR: No network interface found. Cannot set gateway EUI${COLOR_END}"
        fi
        GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
    fi
fi
GATEWAY_EUI=${GATEWAY_EUI^^}

# Push to Balena
[[ "$BALENA_DEVICE_UUID" != "" ]] && balena_set_label "EUI" "$GATEWAY_EUI"

# -----------------------------------------------------------------------------
# URLs
# Defaults to TTN server v3, `eu1` region, 
# use a custom SERVER, CUPS_URI or TC_URI to change this
# If TTS_TENANT is defined different than "ttn", it will be used to build the
# tenant URL under thethings.industries, otherwise only the region will be used
# to build the URL under cloud.thethings.network.
# -----------------------------------------------------------------------------

TTN_REGION=${TTN_REGION:-"eu1"}
TTS_REGION=${TTS_REGION:-$TTN_REGION}
TTS_TENANT=${TTS_TENANT:-"ttn"}
if [[ "$TTS_TENANT" == "ttn" ]]; then
    SERVER=${SERVER:-"${TTS_REGION}.cloud.thethings.network"}
else
    SERVER=${SERVER:-"${TTS_TENANT}.${TTS_REGION}.cloud.thethings.industries"}
fi
CUPS_URI=${CUPS_URI:-"https://${SERVER}:443"} 
TC_URI=${TC_URI:-"wss://${SERVER}:8887"} 

# -----------------------------------------------------------------------------
# Mode (static/dynamic) & protocol (cups/lns)
# -----------------------------------------------------------------------------

# New USE_CUPS variable, will be mandatory in the future
# Possible values are 0 or 1, setting it here to 2 when undefined
USE_CUPS=${USE_CUPS:-2} # undefined by default
PROTOCOL=""

# Configuration mode
if [[ -f ./station.conf ]]; then 
    MODE="STATIC"
    if [[ $USE_CUPS -eq 1 ]]; then
        PROTOCOL="CUPS"
    elif [[ -f ./cups.key ]] && [[ $USE_CUPS -ne 0 ]]; then
        PROTOCOL="CUPS"
        echo -e "${COLOR_WARNING}WARNING: USE_CUPS variable will be mandatory in future versions to enable CUPS${COLOR_END}"
    elif [[ -f ./tc.key ]]; then
        PROTOCOL="LNS"
    elif [[ "$TTS_PERSONAL_KEY" != "" ]] && [[ "$TTS_USERNAME" != "" ]]; then
        tts_autoprovision
        if [[ "$TC_KEY" != "" ]]; then 
            PROTOCOL="LNS"
        fi
    fi
    if [[ "$PROTOCOL" == "" ]]; then
        echo -e "${COLOR_ERROR}ERROR: Custom configuration folder found, but missing files: either force key-less CUPS with USE_CUPS=1 or provide a valid cups.key or tc.key files or TTS_PERSONAL_KEY and TTS_USERNAME variable${COLOR_END}"
        idle
    fi
else
    MODE="DYNAMIC"
    if [[ $USE_CUPS -eq 1 ]]; then
        PROTOCOL="CUPS"
    elif [[ "$CUPS_KEY" != "" ]] && [[ $USE_CUPS -ne 0 ]]; then
        PROTOCOL="CUPS"
        echo -e "${COLOR_WARNING}WARNING: USE_CUPS variable will be mandatory in future versions to enable CUPS${COLOR_END}"
    elif [[ "$TC_KEY" != "" ]]; then 
        PROTOCOL="LNS"
    elif [[ "$TTS_PERSONAL_KEY" != "" ]] && [[ "$TTS_USERNAME" != "" ]]; then
        tts_autoprovision
        if [[ "$TC_KEY" != "" ]]; then 
            PROTOCOL="LNS"
        fi
    fi
    if [[ "$PROTOCOL" == "" ]]; then
        echo -e "${COLOR_ERROR}ERROR: Missing configuration, either force key-less CUPS with USE_CUPS=1 or define valid TC_KEY, CUPS_KEY or TTS_PERSONAL_KEY and TTS_USERNAME${COLOR_END}"
        idle
    fi
fi

# -----------------------------------------------------------------------------
# LNS/CUPS configuration
# -----------------------------------------------------------------------------

# CUPS protocol
if [[ "$PROTOCOL" == "CUPS" ]]; then
    if [[ ! -f ./cups.uri ]]; then 
        echo "$CUPS_URI" > cups.uri
    fi
    if [[ ! -f ./cups.trust ]]; then 
        if [[ "$CUPS_TRUST" == "" ]]; then
            cp /app/cacert.pem cups.trust
        else
            clean_certs_keys "$CUPS_TRUST" > cups.trust
        fi
    fi
    if [[ ! -f ./cups.crt ]]; then 
        if [[ "$CUPS_CRT" != "" ]]; then
            clean_certs_keys "$CUPS_CRT" > cups.crt
        fi
    fi
    if [[ ! -f ./cups.key ]]; then 
        if [[ ! -f ./cups.crt ]]; then 
	        echo "Authorization: Bearer $CUPS_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > cups.key
        else
            clean_certs_keys "$CUPS_KEY" > cups.key
        fi
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
            clean_certs_keys "$TC_TRUST" > tc.trust
        fi
    fi
    if [[ ! -f ./tc.crt ]]; then 
        if [[ "$TC_CRT" != "" ]]; then
            clean_certs_keys "$TC_CRT" > tc.crt
        fi
    fi
    if [[ ! -f ./tc.key ]]; then 
        if [[ ! -f ./tc.crt ]]; then
        	echo "Authorization: Bearer $TC_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > tc.key
        else
            clean_certs_keys "$TC_KEY" > tc.key
        fi
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
    echo -e "${COLOR_ERROR}ERROR: MODEL variable not set${COLOR_END}"
	idle
fi
MODEL=${MODEL^^}
declare -A MODEL_MAP=(
    [RAK7243]=SX1301 [RAK7243C]=SX1301 [RAK7244]=SX1301 [RAK7244C]=SX1301 [RAK7246]=SX1308 [RAK7246G]=SX1308 [RAK7248]=SX1302 [RAK7248C]=SX1302 [RAK7271]=SX1302 [RAK7371]=SX1303 
    [RAK831]=SX1301 [RAK833]=SX1301 [RAK2245]=SX1301 [RAK2246]=SX1308 [RAK2247]=SX1301 [RAK2287]=SX1302 [RAK5146]=SX1303
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
        echo -e "${COLOR_ERROR}ERROR: $DEVICE does not exist${COLOR_END}"
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
    echo -e "${COLOR_ERROR}ERROR: USB interface is not available for SX1301 concentrators${COLOR_END}"
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

USE_LIBGPIOD=${USE_LIBGPIOD:-0}
if [[ $USE_LIBGPIOD -eq 0 ]]; then
    cp /app/reset.sh.legacy reset.sh
else
    cp /app/reset.sh.gpiod reset.sh
fi
sed -i "s#{{RESET_GPIO}}#${GW_RESET_GPIO:-17}#" reset.sh
sed -i "s#{{POWER_EN_GPIO}}#${GW_POWER_EN_GPIO:-0}#" reset.sh
sed -i "s#{{POWER_EN_LOGIC}}#${GW_POWER_EN_LOGIC:-1}#" reset.sh
chmod +x reset.sh

# -----------------------------------------------------------------------------
# Start basicstation
# -----------------------------------------------------------------------------

# Execute packet forwarder
STATION_RADIOINIT=./reset.sh /app/design-${DESIGN}/bin/station -f
