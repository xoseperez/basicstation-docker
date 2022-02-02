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

# Get the variables
source ./info.sh

# Push variables to Balena
push_variables

# Move into configuration folder
mkdir -p config
pushd config >> /dev/null

# Server URI
if [[ ! -f ./tc.uri ]]; then
    if [[ "$TC_URI" == "" ]]; then
        echo -e "\033[91mERROR: Missing configuration, define TC_URI.\033[0m"
	    idle
    fi
    echo "$TC_URI" > tc.uri
fi

# Server Certificate
if [[ ! -f ./tc.trust ]]; then
    if [[ "$TC_TRUST" == "" ]]; then
        echo -e "\033[91mERROR: Missing configuration, define TC_TRUST.\033[0m"
	    idle
    fi
    echo "$TC_TRUST" > tc.trust
fi

# Setup TC files from environment
if [[ ! -f ./tc.key ]]; then
    if [ ! -z ${TC_KEY} ]; then
	    echo "Authorization: Bearer $TC_KEY" | perl -p -e 's/\r\n|\n|\r/\r\n/g'  > tc.key
    fi
fi

# SX1303 uses the same base code as SX1302
if [[ "${CONCENTRATOR}" == "SX1303" ]]; then
    CONCENTRATOR="SX1302"
fi

# Files are in lowercase
CONCENTRATOR=${CONCENTRATOR,,}

# Link the corresponding configuration file
if [[ ! -f ./station.conf ]]; then
    cp /app/station.${CONCENTRATOR}.conf station.conf
    sed -i "s#\"device\":\s*.*,#\"device\": \"$LORAGW_SPI\",#" station.conf
    sed -i "s#\"routerid\":\s*.*,#\"routerid\": \"$GATEWAY_EUI\",#" station.conf
fi

# Reset the concentrator
RESET_GPIO=$GW_RESET_GPIO POWER_EN_GPIO=$GW_POWER_EN_GPIO POWER_EN_LOGIC=$GW_POWER_EN_LOGIC /app/reset.sh

# Execute packet forwarder
/app/${CONCENTRATOR}/bin/station -f

popd >> /dev/null
