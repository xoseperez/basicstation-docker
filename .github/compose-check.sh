#!/usr/bin/env bash

# Checks that docker-compose.yml still parses with each commented setting under
# "environment:" enabled. The settings are tried one at a time, because the
# alternatives share keys (MODEL, DESIGN, DEVICE, INTERFACE,
# GATEWAY_EUI_SOURCE) and enabling them together would hide a broken one.
#
#   .github/compose-check.sh [docker-compose.yml]

set -euo pipefail

FILE=${1:-docker-compose.yml}
WORK=$( mktemp -d )
trap 'rm -rf "${WORK}"' EXIT

# The environment block, from "#environment:" to the next top-level line
mapfile -t LINES < <( awk '
    /^[[:space:]]*#?[[:space:]]?environment:/ { inside = 1; next }
    inside && /^[^[:space:]]/ { inside = 0 }
    inside && /^[[:space:]]*#[[:space:]]?[A-Z][A-Z0-9_]*:/ { print NR }
' "${FILE}" )

if [[ ${#LINES[@]} -eq 0 ]]; then
    echo "::error::no commented settings found under environment: in ${FILE}"
    exit 1
fi

FAILED=0
for LINE in "${LINES[@]}"; do
    # Enable the environment block and this one setting
    sed -E -e "/^[[:space:]]*#[[:space:]]?environment:/s/#[[:space:]]?//" \
        -e "${LINE}s/#[[:space:]]?//" "${FILE}" > "${WORK}/docker-compose.yml"
    SETTING=$( sed -n "${LINE}p" "${WORK}/docker-compose.yml" | sed -E 's/^[[:space:]]+//' )
    if docker compose -f "${WORK}/docker-compose.yml" config -q 2> "${WORK}/error"; then
        echo "ok      ${SETTING}"
    else
        echo "FAILED  ${SETTING}: $( tr '\n' ' ' < "${WORK}/error" )"
        FAILED=1
    fi
done

echo "${#LINES[@]} settings checked"
exit ${FAILED}
