BALENA_DEVICE_DATA=$(curl -sX GET "https://api.balena-cloud.com/v6/device?\$filter=uuid%20eq%20'$BALENA_DEVICE_UUID'" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $BALENA_API_KEY")

BALENA_ID=$(echo $BALENA_DEVICE_DATA | jq ".d | .[0] | .id")

balena_get_lan_ip() {
    echo $BALENA_DEVICE_DATA | jq ".d | .[0] | .ip_address" | sed 's/"//g' | sed 's/ /,/g'
}

balena_set_variable() {
    
    local NAME=$1
    local VALUE=$2
    
    local VARIABLE_ID=$(curl -sX GET "https://api.balena-cloud.com/v6/device_environment_variable" -H "Content-Type: application/json" -H "Authorization: Bearer $BALENA_API_KEY" | jq '.d | .[] | select(.name == "'$NAME'") | .id')
    
    if [ "$VARIABLE_ID" == "" ]; then

        curl -sX POST \
            "https://api.balena-cloud.com/v6/device_environment_variable" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" \
            --data "{\"device\": \"$BALENA_ID\",\"name\": \"$NAME\",\"value\": \"$VALUE\"}" 2> /dev/null

    else

        curl -sX PATCH \
            "https://api.balena-cloud.com/v6/device_environment_variable($VARIABLE_ID)" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" \
            --data "{\"value\": \"$VALUE\"}" 2> /dev/null

    fi

}

balena_set_label() {

    local NAME=$1
    local VALUE=$2

    local TAG_ID=$(curl -sX GET "https://api.balena-cloud.com/v6/device_tag" -H "Content-Type: application/json" -H "Authorization: Bearer $BALENA_API_KEY" | jq '.d | .[] | select(.tag_key == "'$NAME'") | .id')

    if [ "$TAG_ID" == "" ]; then

        curl -sX POST \
            "https://api.balena-cloud.com/v6/device_tag" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" \
            --data "{\"device\": \"$BALENA_ID\",\"tag_key\": \"$NAME\",\"value\": \"$VALUE\"}" 2> /dev/null

    else

        curl -sX PATCH \
            "https://api.balena-cloud.com/v6/device_tag($TAG_ID)" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $BALENA_API_KEY" \
            --data "{\"value\": \"$VALUE\"}" 2> /dev/null

    fi

}


