#!/usr/bin/env bash

# Get the variables
source ./info.sh

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
        cp /app/cacert.pem tc.trust
    else
        TC_TRUST=$(echo $TC_TRUST | sed 's/\s//g' | sed 's/-----BEGINCERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' | sed 's/-----ENDCERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' | sed 's/\n+/\n/g')
        echo "$TC_TRUST" > tc.trust
    fi
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
    sed -i "s#\"device\":\s*.*,#\"device\": \"${INTERFACE,,}:${DEVICE}\",#" station.conf
    sed -i "s#\"routerid\":\s*.*,#\"routerid\": \"$GATEWAY_EUI\",#" station.conf
fi

# If stdn variant (or any *n variant) we need at least one slave concentrator
if [[ ! -f ./slave-0.conf ]]; then
    echo "{}" > slave-0.conf
fi

# Reset the concentrator
RESET_GPIO=$GW_RESET_GPIO POWER_EN_GPIO=$GW_POWER_EN_GPIO POWER_EN_LOGIC=$GW_POWER_EN_LOGIC /app/reset.sh

# Execute packet forwarder
/app/${CONCENTRATOR}/bin/station -f

popd >> /dev/null
