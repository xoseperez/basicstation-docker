#!/usr/bin/env bash

# Checks a built image before it is pushed, without radio hardware. Most checks
# run "start --render", which resolves the settings and writes /app/config the
# way a normal start does, then exits instead of launching station.
#
# - start writes every file, rejects bad settings, and a render writes exactly
#   what a normal start writes; an existing static folder is left alone;
# - the reset script has every placeholder filled, for all three entry points,
#   honours USE_LIBGPIOD, and warns instead of failing silently without a chip;
# - the gateway EUI comes from the requested NIC, then the usual names in their
#   order, then the busiest NIC (never loopback);
# - autoprovisioning, against a mock of The Things Stack API, registers the EUI
#   station uses, stores the key it gets, and reports every failure;
# - certificate chains survive, the default trust is the system CA bundle, and
#   station reads it;
# - static configurations, whitelists, deprecated aliases, the runtime commands,
#   the version banner and the NET mode link.
#
#   ./smoke-test.sh IMAGE PLATFORM
#
# Needs docker, jq and openssl on the host. The NIC checks add a dummy
# interface; without the dummy kernel module they use a second docker network.

set -euo pipefail

IMAGE=$1
PLATFORM=$2

NAME=smoke-bs-$$
LABEL=smoke-bs=$$
HERE=$( cd "$( dirname "$0" )" && pwd )
MOCK_IMAGE=python:3.12-alpine
# Under emulation everything is much slower
RUN_TIMEOUT=${RUN_TIMEOUT:-300}
STATION_TIMEOUT=${STATION_TIMEOUT:-180}

# Station's log holds NUL bytes, which are dropped wherever it is read.
# reset_lgw.sh is an absolute symlink, so folders are compared with
# diff --no-dereference.

# Known MACs, so the expected EUIs are known in advance
MAC_A=02:42:ac:11:00:99
EUI_A=0242ACFFFE110099
MAC_B=02:00:00:00:be:ef
EUI_B=020000FFFE00BEEF

WORK=$( mktemp -d )
COUNTER=0
CURRENT=""
SECTION_START=${SECONDS}

fail() { echo "FAIL: $*" >&2; exit 1; }

# fail_output MESSAGE: fails, showing the end of the last container output
fail_output() {
    printf '%s\n' "${OUTPUT:-}" | tail -n 30 >&2
    fail "$*"
}

# expect TEXT LABEL WANTED... : every WANTED string must appear in TEXT
expect() {
    local text=$1 label=$2 wanted
    shift 2
    for wanted in "$@"; do
        grep -aqF -- "${wanted}" <<< "${text}" || { OUTPUT=${text} fail_output "'${wanted}' missing from the ${label}"; }
    done
}

# reject TEXT LABEL UNWANTED... : no UNWANTED string may appear in TEXT
reject() {
    local text=$1 label=$2 unwanted
    shift 2
    for unwanted in "$@"; do
        if grep -aqF -- "${unwanted}" <<< "${text}"; then
            OUTPUT=${text} fail_output "'${unwanted}' found in the ${label}"
        fi
    done
}

# same A B LABEL : the two values must be equal
same() { [[ "$1" == "$2" ]] || fail "$3: got '$1', expected '$2'"; }

cleanup() {
    docker ps -aq --filter "label=${LABEL}" | xargs -r docker rm -f > /dev/null 2>&1 || true
    docker network rm "${NAME}" "${NAME}-2" > /dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

section() {
    [[ -n "${CURRENT}" ]] && echo "   ${CURRENT}: $(( SECONDS - SECTION_START ))s"
    CURRENT=$1
    SECTION_START=${SECONDS}
    echo "== ${PLATFORM}: $1"
}

for TOOL in docker jq openssl; do
    command -v "${TOOL}" > /dev/null || fail "${TOOL} is needed on the host"
done

# -----------------------------------------------------------------------------
# Containers
# -----------------------------------------------------------------------------

# create [docker create options...] -- [command...]
# Creates a container of the image under test on the run's network and sets
# CONTAINER. Every container carries the run's label, so cleanup finds it.
create() {
    local options=()
    while [[ $# -gt 0 ]] && [[ "$1" != "--" ]]; do
        options+=( "$1" )
        shift
    done
    [[ $# -gt 0 ]] && shift
    COUNTER=$(( COUNTER + 1 ))
    CONTAINER="${NAME}-${COUNTER}"
    docker create --name "${CONTAINER}" --label "${LABEL}" --platform "${PLATFORM}" \
        --network "${NAME}" "${options[@]}" "${IMAGE}" "$@" > /dev/null
}

# overlay DIR : copies DIR into the container's root, so DIR/app/config/x
# becomes /app/config/x. Each container gets its own copy of the files.
overlay() {
    [[ -n "$1" ]] && docker cp -q "$1/." "${CONTAINER}:/"
    return 0
}

# run_in FROM TO OVERLAY [options...] -- [command...]
# Runs a container to completion, then copies its FROM folder to TO on the host
# (skipped when FROM is empty). Sets OUTPUT and STATUS.
run_in() {
    local from=$1 to=$2 dir=$3
    shift 3
    create "$@"
    overlay "${dir}"
    STATUS=0
    OUTPUT=$( timeout "${RUN_TIMEOUT}" docker start -a "${CONTAINER}" 2>&1 ) || STATUS=$?
    [[ ${STATUS} -eq 124 ]] && fail_output "${CONTAINER} did not finish within ${RUN_TIMEOUT}s"
    if [[ -n "${from}" ]]; then
        rm -rf "${to}"
        mkdir -p "$( dirname "${to}" )"
        docker cp -q "${CONTAINER}:${from}" "${to}"
    fi
    docker rm -f "${CONTAINER}" > /dev/null
}

# run_station TO OVERLAY MARKER [options...] -- [command...]
# Starts a long-running container and waits until MARKER shows in its log. The
# container is left running as RUNNING, with its /app/config copied to TO
# (when not empty) and its log in OUTPUT.
run_station() {
    local to=$1 dir=$2 marker=$3 deadline
    shift 3
    create "$@"
    overlay "${dir}"
    docker start "${CONTAINER}" > /dev/null
    RUNNING=${CONTAINER}
    deadline=$(( SECONDS + STATION_TIMEOUT ))
    until docker logs "${RUNNING}" 2>&1 | grep -aqF -- "${marker}"; do
        if (( SECONDS > deadline )) || [[ "$( docker inspect -f '{{.State.Running}}' "${RUNNING}" )" != "true" ]]; then
            OUTPUT=$( docker logs "${RUNNING}" 2>&1 | tr -d '\0' )
            fail_output "'${marker}' did not show in the log of ${RUNNING}"
        fi
        sleep 1
    done
    OUTPUT=$( docker logs "${RUNNING}" 2>&1 | tr -d '\0' )
    if [[ -n "${to}" ]]; then
        rm -rf "${to}"
        docker cp -q "${RUNNING}:/app/config" "${to}"
    fi
}

stop_station() { docker rm -f "${RUNNING}" > /dev/null; }

# A folder of cases run in one container: each line is NAME|COMMAND|ENV...,
# run with a clean /app/config. Its output, exit status and files are kept in
# /tmp/cases/NAME. Batching keeps the number of containers, which are slow to
# start under emulation, down.
# shellcheck disable=SC2016
BATCH='
mkdir -p /tmp/cases
while IFS="|" read -r NAME COMMAND ENVS; do
    rm -rf /app/config /app/reset_lgw.sh
    mkdir -p /app/config "/tmp/cases/${NAME}"
    # shellcheck disable=SC2086
    env ${ENVS} bash -c "${COMMAND}" > "/tmp/cases/${NAME}/output" 2>&1
    echo $? > "/tmp/cases/${NAME}/status"
    cp -a /app/config "/tmp/cases/${NAME}/config"
    if [ -f /app/reset_lgw.sh ]; then cp /app/reset_lgw.sh "/tmp/cases/${NAME}/reset_lgw.sh"; fi
done < /tmp/cases.txt
'

# batch TO OVERLAY [options...] : runs the cases in OVERLAY/tmp/cases.txt
batch() {
    local to=$1 dir=$2
    shift 2
    run_in /tmp/cases "${to}" "${dir}" "$@" -- bash -c "${BATCH}"
    [[ ${STATUS} -eq 0 ]] || fail_output "the case runner failed"
}
case_status() { cat "$1/$2/status"; }
case_output() { cat "$1/$2/output"; }

# jq_file FILE FILTER : one value from a JSON file
jq_file() { jq -r "$2" "$1"; }

# eui MAC : the EUI-64 start derives from a MAC address
eui() { local m=${1//:/}; m=${m^^}; echo "${m:0:6}FFFE${m:6:6}"; }

same "$( eui "${MAC_A}" )" "${EUI_A}" "EUI of MAC_A"
same "$( eui "${MAC_B}" )" "${EUI_B}" "EUI of MAC_B"

docker network create "${NAME}" > /dev/null

# -----------------------------------------------------------------------------
# Test material: certificates and the mock API
# -----------------------------------------------------------------------------

M=${WORK}/material
mkdir -p "${M}"
(
    cd "${M}"
    # The mock's CA and server certificate (SAN tts-mock)
    openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -subj /CN=smoke-ca 2> /dev/null
    openssl req -newkey rsa:2048 -nodes -keyout mock.key -out mock.csr -subj /CN=tts-mock 2> /dev/null
    printf 'subjectAltName=DNS:tts-mock\nbasicConstraints=CA:FALSE\n' > mock.ext
    openssl x509 -req -in mock.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 \
        -extfile mock.ext -out mock.pem 2> /dev/null
    # A two-certificate chain (intermediate + root) and a private key
    openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.pem -days 2 -subj /CN=smoke-root 2> /dev/null
    openssl req -newkey rsa:2048 -nodes -keyout inter.key -out inter.csr -subj /CN=smoke-intermediate 2> /dev/null
    printf 'basicConstraints=CA:TRUE\n' > inter.ext
    openssl x509 -req -in inter.csr -CA root.pem -CAkey root.key -CAcreateserial -days 2 \
        -extfile inter.ext -out inter.pem 2> /dev/null
    cat inter.pem root.pem > chain.pem
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out client.key 2> /dev/null
) || fail "could not create the test certificates"
CHAIN=$( < "${M}/chain.pem" )
CLIENT_KEY=$( < "${M}/client.key" )

# certs FILE : the number of certificates openssl reads from FILE
certs() {
    openssl crl2pkcs7 -nocrl -certfile "$1" 2> /dev/null | openssl pkcs7 -print_certs -noout 2> /dev/null | grep -c '^subject' || true
}

# The CA the image under test trusts for the mock, through CURL_CA_BUNDLE only
CA_OVERLAY=${WORK}/ca-overlay
mkdir -p "${CA_OVERLAY}/tmp"
cp "${M}/ca.pem" "${CA_OVERLAY}/tmp/smoke-ca.pem"

start_mock() {
    local deadline dir=${WORK}/mock-overlay
    mkdir -p "${dir}/mock" "${dir}/records"
    cp "${HERE}/smoke/tts-mock.py" "${M}/mock.pem" "${M}/mock.key" "${dir}/mock/"
    echo ok > "${dir}/records/mode"
    : > "${dir}/records/requests.jsonl"
    docker create --name "${NAME}-mock" --label "${LABEL}" --network "${NAME}" --network-alias tts-mock \
        "${MOCK_IMAGE}" python3 /mock/tts-mock.py /mock/mock.pem /mock/mock.key > /dev/null
    docker cp -q "${dir}/." "${NAME}-mock:/"
    docker start "${NAME}-mock" > /dev/null
    deadline=$(( SECONDS + 60 ))
    until docker logs "${NAME}-mock" 2>&1 | grep -qF "tts-mock listening"; do
        (( SECONDS > deadline )) && { docker logs "${NAME}-mock" >&2; fail "the mock API did not start"; }
        sleep 1
    done
}

# mock MODE : sets how the mock answers and forgets the recorded requests
mock() { docker exec "${NAME}-mock" sh -c "echo $1 > /records/mode && : > /records/requests.jsonl"; }
requests() { docker exec "${NAME}-mock" cat /records/requests.jsonl; }

# -----------------------------------------------------------------------------
# start --render
# -----------------------------------------------------------------------------

section "render"
D=${WORK}/render
run_in /app/config "${D}" "" --mac-address "${MAC_A}" -e MODEL=RAK5146 -e TC_KEY=x -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "start --render exited ${STATUS}"
for FILE in station.conf slave-0.conf tc.uri tc.trust tc.key reset.sh; do
    [[ -f "${D}/${FILE}" ]] || fail_output "start --render did not write ${FILE}"
done
same "$( jq_file "${D}/station.conf" .station_conf.routerid )" "${EUI_A}" "routerid"
same "$( jq_file "${D}/station.conf" .SX1302_conf.device )" "spi:/dev/spidev0.0" "device"
expect "${OUTPUT}" "render output" "does not exist (ignored by --render)" "Mode:          DYNAMIC"

section "bad settings are rejected"
run_in "" "" "" -e MODEL=NOPE -e TC_KEY=x -- start --render
[[ ${STATUS} -ne 0 ]] || fail_output "MODEL=NOPE was accepted"
expect "${OUTPUT}" "bad MODEL output" "Unknown MODEL value (NOPE)"
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- start --nope
[[ ${STATUS} -ne 0 ]] || fail_output "start --nope was accepted"
expect "${OUTPUT}" "bad option output" "Unknown option '--nope'"
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- start --autoprovision
[[ ${STATUS} -ne 0 ]] || fail_output "start --autoprovision without --render was accepted"
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- start
[[ ${STATUS} -ne 0 ]] || fail_output "a normal start without the radio device did not stop"
expect "${OUTPUT}" "normal start output" "ERROR: /dev/spidev0.0 does not exist"

section "render writes what a normal start writes"
# A stand-in device lets the normal start get as far as station, which then
# fails to reach the unreachable LNS and keeps retrying.
STAND_IN=( --device /dev/null:/dev/spidev0.0 --mac-address "${MAC_A}" )
DYNAMIC=( "${STAND_IN[@]}" -e MODEL=RAK5146 -e TC_KEY=x -e TC_URI=wss://127.0.0.1:1 )
run_station "${WORK}/normal-dynamic" "" "Starting TC engine" "${DYNAMIC[@]}" -- start
stop_station
run_in /app/config "${WORK}/render-dynamic" "" "${DYNAMIC[@]}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render exited ${STATUS}"
diff -r --no-dereference "${WORK}/normal-dynamic" "${WORK}/render-dynamic" || fail "DYNAMIC: render and normal start wrote different files"

# An existing static folder, as left by an earlier version: station.conf, the
# connection files and a tc.trust that is not today's default bundle. Each run
# gets its own copy, and the files must come back byte for byte.
FIXTURE=${WORK}/static-fixture
mkdir -p "${FIXTURE}/app/config"
jq '.station_conf.routerid = "AABBCCDDEEFF0011" | .SX1302_conf.device = "spi:/dev/spidev0.0"' \
    "${HERE}/runner/station.corecell.conf" > "${FIXTURE}/app/config/station.conf"
echo "wss://127.0.0.1:1" > "${FIXTURE}/app/config/tc.uri"
printf 'Authorization: Bearer fixture-key\r\n' > "${FIXTURE}/app/config/tc.key"
cp "${M}/root.pem" "${FIXTURE}/app/config/tc.trust"
run_station "${WORK}/normal-static" "${FIXTURE}" "Starting TC engine" "${STAND_IN[@]}" -- start
expect "${OUTPUT}" "static start output" "Mode:          STATIC"
stop_station
run_in /app/config "${WORK}/render-static" "${FIXTURE}" "${STAND_IN[@]}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "static render exited ${STATUS}"
expect "${OUTPUT}" "static render output" "Mode:          STATIC"
diff -r --no-dereference "${WORK}/normal-static" "${WORK}/render-static" || fail "STATIC: render and normal start wrote different files"
for RUN in normal-static render-static; do
    for FILE in station.conf tc.uri tc.key tc.trust; do
        cmp -s "${FIXTURE}/app/config/${FILE}" "${WORK}/${RUN}/${FILE}" || fail "${RUN} changed the existing ${FILE}"
    done
    # start adds only the files it writes on every start
    ADDED=$( find "${WORK}/${RUN}" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        | grep -vxE 'station.conf|tc.uri|tc.key|tc.trust|reset.sh|reset_lgw.sh|slave-0.conf' || true )
    [[ -z "${ADDED}" ]] || fail "${RUN} added unexpected files: ${ADDED}"
done
echo "static folder unchanged:"
( cd "${FIXTURE}/app/config" && find . -type f | LC_ALL=C sort | xargs sha256sum )

# -----------------------------------------------------------------------------
# Reset script
# -----------------------------------------------------------------------------

section "reset script, for each entry point"
# No /dev/gpiochip* in the container, so only the given chips can appear
RESET_CASES=(
    "chip_r|GPIO_CHIP=chipG RESET_GPIO_CHIP=chipR"
    "chip_e|GPIO_CHIP=chipG ENABLE_GPIO_CHIP=chipE"
    "chip_g|GPIO_CHIP=chipG"
    "sysfs|USE_LIBGPIOD=0"
    "libgpiod|USE_LIBGPIOD=1"
    "default|"
)
for CALLER in start find_concentrator gateway_eui; do
    case "${CALLER}" in
        start) COMMAND="start --render > /dev/null; cat /app/config/reset.sh"; RESET="17" ;;
        *) COMMAND="${CALLER} > /dev/null; cat /app/reset_lgw.sh"; RESET="6,17" ;;
    esac
    DIR=${WORK}/reset-${CALLER}
    mkdir -p "${DIR}/tmp"
    for CASE in "${RESET_CASES[@]}"; do
        echo "${CASE%%|*}|${COMMAND}|MODEL=RAK5146 TC_KEY=x ${CASE#*|}"
    done > "${DIR}/tmp/cases.txt"
    batch "${WORK}/reset-${CALLER}-out" "${DIR}" --mac-address "${MAC_A}"
    R=${WORK}/reset-${CALLER}-out
    for CASE in "${RESET_CASES[@]}"; do
        C=${CASE%%|*}
        TEXT=$( case_output "${R}" "${C}" )
        reject "${TEXT}" "${CALLER} reset script (${C})" "{{"
        expect "${TEXT}" "${CALLER} reset script (${C})" \
            "RESET_GPIO=\"${RESET}\"" "POWER_EN_GPIO=\"0\"" "POWER_EN_LOGIC=\"1\""
    done
    expect "$( case_output "${R}" chip_r )" "${CALLER} reset script" 'RESET_GPIO_CHIP="chipR"' 'ENABLE_GPIO_CHIP="chipG"'
    expect "$( case_output "${R}" chip_e )" "${CALLER} reset script" 'RESET_GPIO_CHIP="chipG"' 'ENABLE_GPIO_CHIP="chipE"'
    expect "$( case_output "${R}" chip_g )" "${CALLER} reset script" 'RESET_GPIO_CHIP="chipG"' 'ENABLE_GPIO_CHIP="chipG"'
    expect "$( case_output "${R}" sysfs )" "${CALLER} reset script, USE_LIBGPIOD=0" "using sysfs"
    reject "$( case_output "${R}" sysfs )" "${CALLER} reset script, USE_LIBGPIOD=0" "using libgpiod"
    expect "$( case_output "${R}" libgpiod )" "${CALLER} reset script, USE_LIBGPIOD=1" "using libgpiod"
    expect "$( case_output "${R}" default )" "${CALLER} reset script, USE_LIBGPIOD unset" "using libgpiod"
done

section "reset script without a GPIO chip"
# A stub gpioset records every call
# shellcheck disable=SC2016
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- bash -c '
    mkdir -p /tmp/stub
    printf "#!/bin/sh\necho \"\$*\" >> /tmp/stub/log\n" > /tmp/stub/gpioset
    chmod +x /tmp/stub/gpioset
    start --render > /dev/null
    echo "=== no chip"
    PATH=/tmp/stub:$PATH bash /app/config/reset.sh
    echo "calls: $( cat /tmp/stub/log 2> /dev/null )"
    rm -rf /app/config/*
    GPIO_CHIP=chipG start --render > /dev/null
    echo "=== chipG"
    PATH=/tmp/stub:$PATH bash /app/config/reset.sh
    echo "calls: $( cat /tmp/stub/log 2> /dev/null )"'
[[ ${STATUS} -eq 0 ]] || fail_output "the no-chip check exited ${STATUS}"
NO_CHIP=$( sed -n '/=== no chip/,/=== chipG/p' <<< "${OUTPUT}" )
expect "${NO_CHIP}" "reset output without a chip" \
    "WARNING: no GPIO chip given or detected, the concentrator is not reset (set GPIO_CHIP)" "calls: "
reject "${NO_CHIP}" "reset output without a chip" "calls: -"
expect "$( sed -n '/=== chipG/,$p' <<< "${OUTPUT}" )" "reset output with GPIO_CHIP=chipG" \
    "calls: -m time -u 100000 chipG 17=0"

# -----------------------------------------------------------------------------
# Gateway EUI from a NIC
# -----------------------------------------------------------------------------

section "gateway EUI from a network interface"
# Interface A (MAC_A) is renamed eth0. Interface B (MAC_B) is a dummy
# interface, or, without the dummy kernel module, the interface of a second
# network. B starts as dummy0, so it is not one of the names tried first.
if [[ -d /sys/module/dummy ]]; then
    NIC_METHOD=dummy
else
    NIC_METHOD=eth1
    docker network create "${NAME}-2" > /dev/null
fi
echo "second interface: ${NIC_METHOD}"
# 1 MB of traffic for the busiest-interface check
create --network-alias nicfeed -- socat TCP-LISTEN:9000,reuseaddr,fork "SYSTEM:head -c 1048576 /dev/zero"
docker start "${CONTAINER}" > /dev/null

# shellcheck disable=SC2016
NIC_SCRIPT='
set -u
rn() { ip link set "$1" down && ip link set "$1" name "$2" && ip link set "$2" up; }
render_eui() {
    rm -rf /app/config/*
    env "$@" MODEL=RAK5146 TC_KEY=x start --render > /tmp/render.out 2>&1
    jq -r .station_conf.routerid /app/config/station.conf 2> /dev/null
}
helper_eui() {
    # gateway_eui reads a station.conf first, so the last render must not be there
    rm -rf /app/config/*
    env "$@" gateway_eui 2>&1 | tee /tmp/helper.out | sed -n "s/^Gateway EUI: \([0-9A-F]*\).*/\1/p"
}
both() {   # NAME ENV... : the EUI from start and from gateway_eui
    local name=$1; shift
    echo "$name render $(render_eui "$@")"
    echo "$name helper $(helper_eui "$@")"
}
# A is the interface docker gave MAC_A, on the network the traffic source is
# on. With two networks docker may name it eth1, so it is found by its MAC.
A=""; OTHER=""
for P in /sys/class/net/*; do
    N=${P##*/}
    [ "$N" = lo ] && continue
    if [ "$(cat "$P/address")" = "$MAC_A" ]; then A=$N; else OTHER=$N; fi
done
[ -n "$A" ] || { echo "SETUP failed: no interface with $MAC_A"; exit 1; }
if [ "$NIC_METHOD" = dummy ]; then
    [ "$A" = eth0 ] || rn "$A" eth0
    ip link add dummy0 address "$MAC_B" type dummy && ip link set dummy0 up || { echo "SETUP failed: dummy"; exit 1; }
else
    [ -n "$OTHER" ] || { echo "SETUP failed: no second interface"; exit 1; }
    rn "$OTHER" parkb && { [ "$A" = eth0 ] || rn "$A" eth0; } && ip link set parkb down && ip link set parkb address "$MAC_B" \
        && ip link set parkb name dummy0 && ip link set dummy0 up || { echo "SETUP failed: eth1"; exit 1; }
fi
AN=eth0; BN=dummy0
name_a() { rn "$AN" "$1" && AN=$1; }
name_b() { rn "$BN" "$1" && BN=$1; }
both requested GATEWAY_EUI_SOURCE=dummy0
both missing GATEWAY_EUI_SOURCE=nope0
echo "missing warning render $(grep -c "GATEWAY_EUI_SOURCE is .nope0." /tmp/render.out)"
helper_eui GATEWAY_EUI_SOURCE=nope0 > /dev/null
echo "missing warning helper $(grep -c "GATEWAY_EUI_SOURCE is .nope0." /tmp/helper.out)"
both both_names GATEWAY_EUI_SOURCE=dummy0 GATEWAY_EUI_NIC=eth0
both alias GATEWAY_EUI_NIC=dummy0
# Busiest: no preferred name left, B idle, A receives 1 MB
name_a ext0
BEFORE=$(cat /sys/class/net/ext0/statistics/rx_bytes)
for i in $(seq 1 30); do exec 3< /dev/tcp/nicfeed/9000 2> /dev/null && break; sleep 1; done
cat <&3 > /dev/null; exec 3<&-
AFTER=$(cat /sys/class/net/ext0/statistics/rx_bytes)
echo "busiest rx $(( AFTER - BEFORE ))"
both busiest
name_a eth0
# Name order, pair by pair and both ways round: whichever interface has the
# earlier name must win, so neither the interface index nor the original
# names can explain the result
pair() {
    name_a pa; name_b pb; name_b "$1"; name_a "$2"; both "order_$1_$2_b"
    name_a pa; name_b pb; name_a "$1"; name_b "$2"; both "order_$1_$2_a"
}
pair eth0 wlan0
pair wlan0 usb0
pair usb0 eth1
'
NIC_OPTIONS=( --cap-add NET_ADMIN --mac-address "${MAC_A}" -e NIC_METHOD="${NIC_METHOD}" -e MAC_A="${MAC_A}" -e MAC_B="${MAC_B}" )
create "${NIC_OPTIONS[@]}" -- bash -c "${NIC_SCRIPT}"
[[ "${NIC_METHOD}" == "eth1" ]] && docker network connect "${NAME}-2" "${CONTAINER}"
STATUS=0
OUTPUT=$( timeout "${RUN_TIMEOUT}" docker start -a "${CONTAINER}" 2>&1 ) || STATUS=$?
docker rm -f "${CONTAINER}" > /dev/null
[[ ${STATUS} -eq 0 ]] || fail_output "the NIC checks exited ${STATUS}"
reject "${OUTPUT}" "NIC check output" "SETUP failed"
nic() { sed -n "s/^$1 $2 //p" <<< "${OUTPUT}"; }
for WHO in render helper; do
    same "$( nic requested "${WHO}" )" "${EUI_B}" "GATEWAY_EUI_SOURCE=dummy0 (${WHO})"
    same "$( nic missing "${WHO}" )" "${EUI_A}" "GATEWAY_EUI_SOURCE=nope0 (${WHO})"
    same "$( sed -n "s/^missing warning ${WHO} //p" <<< "${OUTPUT}" )" "1" "warning for a missing NIC (${WHO})"
    same "$( nic both_names "${WHO}" )" "${EUI_B}" "GATEWAY_EUI_SOURCE wins over GATEWAY_EUI_NIC (${WHO})"
    same "$( nic alias "${WHO}" )" "${EUI_B}" "GATEWAY_EUI_NIC=dummy0 (${WHO})"
    same "$( nic busiest "${WHO}" )" "${EUI_A}" "busiest NIC (${WHO})"
    for PAIR in order_eth0_wlan0 order_wlan0_usb0 order_usb0_eth1; do
        same "$( nic "${PAIR}_b" "${WHO}" )" "${EUI_B}" "${PAIR}, B with the earlier name (${WHO})"
        same "$( nic "${PAIR}_a" "${WHO}" )" "${EUI_A}" "${PAIR}, A with the earlier name (${WHO})"
    done
done
RX=$( sed -n 's/^busiest rx //p' <<< "${OUTPUT}" )
(( RX >= 1048576 )) || fail "ext0 received ${RX} bytes, expected at least 1048576"
docker ps -aq --filter "label=${LABEL}" | xargs -r docker rm -f > /dev/null

# -----------------------------------------------------------------------------
# Autoprovisioning
# -----------------------------------------------------------------------------

section "autoprovisioning"
start_mock
TTS=( -e TTS_PERSONAL_KEY=smoke-personal-key -e TTS_USERNAME=smoke-user -e SERVER=tts-mock
    -e CURL_CA_BUNDLE=/tmp/smoke-ca.pem -e MODEL=RAK5146 --mac-address "${MAC_A}" )
TC_KEY_FILE=$( printf 'Authorization: Bearer NNSXS.SMOKETEST.MOCKKEY\r\n' )

# check_provisioned DIR EUI : the mock saw the registration of EUI and the key
# rotation, and the issued key reached tc.key
check_provisioned() {
    local dir=$1 eui=$2 log
    log=$( requests )
    same "$( jq_file "${dir}/station.conf" .station_conf.routerid )" "$2" "written routerid"
    same "$( jq -r 'select(.method == "POST" and (.path | endswith("/gateways"))) | .body.gateway.ids.eui' <<< "${log}" )" \
        "${eui}" "registered EUI"
    same "$( jq -r 'select(.method == "POST" and (.path | endswith("/gateways"))) | .body.gateway.ids.gateway_id' <<< "${log}" )" \
        "eui-${eui,,}" "registered gateway ID"
    same "$( jq -r 'select(.method == "PUT") | .path' <<< "${log}" )" \
        "/api/v3/gateways/eui-${eui,,}/api-keys/OLDKEY" "revoked key"
    same "$( jq -r '.headers.Authorization' <<< "${log}" | sort -u )" "Bearer smoke-personal-key" "API authorization"
    same "$( < "${dir}/tc.key" )" "${TC_KEY_FILE}" "tc.key"
}

STATIC_ROUTERID=${WORK}/static-routerid
mkdir -p "${STATIC_ROUTERID}/app/config"
cp -r "${CA_OVERLAY}/." "${STATIC_ROUTERID}/"
jq '.station_conf.routerid = "AABBCCDDEEFF0011" | .SX1302_conf.device = "spi:/dev/spidev0.0"' \
    "${HERE}/runner/station.corecell.conf" > "${STATIC_ROUTERID}/app/config/station.conf"

mock ok
run_in /app/config "${WORK}/ap-nic" "${CA_OVERLAY}" "${TTS[@]}" -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "autoprovisioning (NIC EUI) exited ${STATUS}"
expect "${OUTPUT}" "autoprovisioning output" "Gateway autoprovisioned successfully!" "TC_KEY successfully generated"
check_provisioned "${WORK}/ap-nic" "${EUI_A}"

mock exists
run_in /app/config "${WORK}/ap-env" "${CA_OVERLAY}" "${TTS[@]}" -e GATEWAY_EUI=0011223344556677 -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "autoprovisioning (GATEWAY_EUI) exited ${STATUS}"
expect "${OUTPUT}" "autoprovisioning output" "WARNING: The gateway was already provisioned."
check_provisioned "${WORK}/ap-env" "0011223344556677"

mock ok
run_in /app/config "${WORK}/ap-static" "${STATIC_ROUTERID}" "${TTS[@]}" -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "autoprovisioning (STATIC) exited ${STATUS}"
check_provisioned "${WORK}/ap-static" "AABBCCDDEEFF0011"

mock ok
run_in /app/config "${WORK}/ap-static-env" "${STATIC_ROUTERID}" "${TTS[@]}" -e GATEWAY_EUI=1111111111111111 -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "autoprovisioning (STATIC with GATEWAY_EUI) exited ${STATUS}"
check_provisioned "${WORK}/ap-static-env" "AABBCCDDEEFF0011"
expect "${OUTPUT}" "STATIC summary" "Gateway EUI:   AABBCCDDEEFF0011" "EUI Source:    file"

section "autoprovisioning only on request, and its errors"
mock ok
run_in /app/config "${WORK}/ap-skipped" "${CA_OVERLAY}" "${TTS[@]}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with TTS credentials exited ${STATUS}"
expect "${OUTPUT}" "render output" "Autoprovisioning skipped (use --autoprovision); tc.key not written, this output is not ready to run"
[[ ! -e "${WORK}/ap-skipped/tc.key" ]] || fail "a render without --autoprovision wrote tc.key"
[[ -z "$( requests )" ]] || fail "a render without --autoprovision called the API"

# Each failure reports it, never claims a key, and stops with today's error
for CASE in "unreachable|ok|-e SERVER=tts-mock:1" "nokey|nokey|" "emptykey|emptykey|"; do
    IFS='|' read -r WHAT MODE EXTRA <<< "${CASE}"
    mock "${MODE}"
    # shellcheck disable=SC2086
    run_in "" "" "${CA_OVERLAY}" "${TTS[@]}" ${EXTRA} -- start --render --autoprovision
    [[ ${STATUS} -ne 0 ]] || fail_output "autoprovisioning (${WHAT}) did not fail"
    expect "${OUTPUT}" "autoprovisioning output (${WHAT})" "ERROR: Autoprovisioning returned no key" \
        "ERROR: Missing configuration"
    reject "${OUTPUT}" "autoprovisioning output (${WHAT})" "successfully generated"
done
expect "${OUTPUT}" "autoprovisioning output (emptykey)" "Gateway autoprovisioned successfully!"

NO_ROUTERID=${WORK}/static-no-routerid
mkdir -p "${NO_ROUTERID}/app/config"
jq 'del(.station_conf.routerid)' "${HERE}/runner/station.corecell.conf" > "${NO_ROUTERID}/app/config/station.conf"
BAD_ROUTERID=${WORK}/static-bad-routerid
mkdir -p "${BAD_ROUTERID}/app/config"
jq '.station_conf.routerid = "nothex"' "${HERE}/runner/station.corecell.conf" > "${BAD_ROUTERID}/app/config/station.conf"
mock ok
run_in "" "" "${NO_ROUTERID}" "${TTS[@]}" -- start --render --autoprovision
[[ ${STATUS} -ne 0 ]] || fail_output "autoprovisioning a STATIC config without routerid did not fail"
expect "${OUTPUT}" "output without routerid" "station.conf has no routerid"
run_in "" "" "${BAD_ROUTERID}" "${TTS[@]}" -- start --render --autoprovision
[[ ${STATUS} -ne 0 ]] || fail_output "autoprovisioning routerid 'nothex' did not fail"
expect "${OUTPUT}" "output with routerid nothex" "Cannot autoprovision the gateway EUI 'NOTHEX'"
run_in "" "" "${CA_OVERLAY}" "${TTS[@]}" -e USE_CUPS=1 -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "USE_CUPS=1 with TTS credentials exited ${STATUS}"
expect "${OUTPUT}" "USE_CUPS=1 output" "Protocol:      CUPS"
[[ -z "$( requests )" ]] || fail "the API was called without a valid EUI or with CUPS forced"

# A name with quotes and a backslash reaches the API intact
QUOTED='a "quoted" \ name'
mock ok
run_in "" "" "${CA_OVERLAY}" "${TTS[@]}" -e "GATEWAY_NAME=${QUOTED}" -- start --render --autoprovision
[[ ${STATUS} -eq 0 ]] || fail_output "autoprovisioning with a quoted name exited ${STATUS}"
same "$( requests | jq -r 'select(.path | endswith("/gateways")) | .body.gateway.name' )" "${QUOTED}" "gateway name"

# -----------------------------------------------------------------------------
# Certificates and trust
# -----------------------------------------------------------------------------

section "certificate chains"
check_chain() {   # FILE LABEL
    same "$( grep -c 'BEGIN CERTIFICATE' "$1" )" "2" "certificates in $2"
    same "$( certs "$1" )" "2" "certificates openssl reads from $2"
}
run_in /app/config "${WORK}/tc-env" "" -e MODEL=RAK5146 -e "TC_TRUST=${CHAIN}" -e "TC_CRT=${CHAIN}" \
    -e "TC_KEY=${CLIENT_KEY}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with TC_* certificates exited ${STATUS}"
check_chain "${WORK}/tc-env/tc.trust" "tc.trust from TC_TRUST"
check_chain "${WORK}/tc-env/tc.crt" "tc.crt from TC_CRT"
openssl pkey -in "${WORK}/tc-env/tc.key" -noout 2> /dev/null || fail "tc.key from TC_KEY is not a valid key"
run_in /app/config "${WORK}/cups-env" "" -e MODEL=RAK5146 -e USE_CUPS=1 -e "CUPS_TRUST=${CHAIN}" \
    -e "CUPS_CRT=${CHAIN}" -e "CUPS_KEY=${CLIENT_KEY}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with CUPS_* certificates exited ${STATUS}"
check_chain "${WORK}/cups-env/cups.trust" "cups.trust from CUPS_TRUST"
check_chain "${WORK}/cups-env/cups.crt" "cups.crt from CUPS_CRT"
openssl pkey -in "${WORK}/cups-env/cups.key" -noout 2> /dev/null || fail "cups.key from CUPS_KEY is not a valid key"
# One set per protocol: a cups.key secret alone already selects CUPS
for PROTO in tc cups; do
    mkdir -p "${WORK}/${PROTO}-secret-files/run/secrets"
    cp "${M}/chain.pem" "${WORK}/${PROTO}-secret-files/run/secrets/${PROTO}.trust"
    cp "${M}/chain.pem" "${WORK}/${PROTO}-secret-files/run/secrets/${PROTO}.crt"
    cp "${M}/client.key" "${WORK}/${PROTO}-secret-files/run/secrets/${PROTO}.key"
done
run_in /app/config "${WORK}/tc-secrets" "${WORK}/tc-secret-files" -e MODEL=RAK5146 -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with tc.* secrets exited ${STATUS}"
check_chain "${WORK}/tc-secrets/tc.trust" "tc.trust from /run/secrets"
check_chain "${WORK}/tc-secrets/tc.crt" "tc.crt from /run/secrets"
run_in /app/config "${WORK}/cups-secrets" "${WORK}/cups-secret-files" -e MODEL=RAK5146 -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with cups.* secrets exited ${STATUS}"
check_chain "${WORK}/cups-secrets/cups.trust" "cups.trust from /run/secrets"
check_chain "${WORK}/cups-secrets/cups.crt" "cups.crt from /run/secrets"
# Line breaks lost, or turned into spaces, as happens with environment variables
run_in /app/config "${WORK}/tc-mangled" "" -e MODEL=RAK5146 -e TC_KEY=x \
    -e "TC_TRUST=$( tr -d '\n' <<< "${CHAIN}" )" -e "TC_CRT=$( tr '\n' ' ' <<< "${CHAIN}" )" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "render with mangled certificates exited ${STATUS}"
check_chain "${WORK}/tc-mangled/tc.trust" "tc.trust from a single-line PEM"
check_chain "${WORK}/tc-mangled/tc.crt" "tc.crt from a space-separated PEM"

section "default trust"
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- bash -c '
    start --render > /dev/null && cmp /app/config/tc.trust /etc/ssl/certs/ca-certificates.crt && echo "tc.trust is the system bundle"
    rm -rf /app/config/*
    USE_CUPS=1 start --render > /dev/null && cmp /app/config/cups.trust /etc/ssl/certs/ca-certificates.crt && echo "cups.trust is the system bundle"'
expect "${OUTPUT}" "default trust check" "tc.trust is the system bundle" "cups.trust is the system bundle"

section "station reads the default trust"
# Station rejects the whole trust file if one certificate fails to parse. It
# logs "./tc.trust:" only after a successful parse, before it connects.
run_station "" "" "Connecting to INFOS" "${STAND_IN[@]}" -e MODEL=RAK5146 -e TC_KEY=x \
    -e TC_URI=wss://tts-mock:8887 -- start
stop_station
expect "${OUTPUT}" "station log" "./tc.trust:" "Connecting to INFOS: wss://tts-mock:8887"
reject "${OUTPUT}" "station log" "Parsing trusted certificate" "X509 -"

# -----------------------------------------------------------------------------
# Static configurations and whitelists
# -----------------------------------------------------------------------------

section "static station.conf without routerid or device"
NO_KEYS=${WORK}/static-no-keys
mkdir -p "${NO_KEYS}/app/config"
jq 'del(.station_conf.routerid) | del(.SX1302_conf.device)' "${HERE}/runner/station.corecell.conf" \
    > "${NO_KEYS}/app/config/station.conf"
printf 'Authorization: Bearer fixture-key\r\n' > "${NO_KEYS}/app/config/tc.key"
run_in /app/config "${WORK}/no-keys" "${NO_KEYS}" --mac-address "${MAC_A}" -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "static render without routerid exited ${STATUS}"
reject "${OUTPUT}" "static summary" "NULL" "null"
expect "${OUTPUT}" "static summary" "Mode:          STATIC" "Gateway EUI:   ${EUI_A}" "EUI Source:    eth0" \
    "Radio Device:  /dev/spidev0.0" "WARNING: station.conf has no routerid, station may use a different EUI than the one shown"
cmp -s "${NO_KEYS}/app/config/station.conf" "${WORK}/no-keys/station.conf" || fail "the static station.conf was changed"

section "static summary"
SUMMARY=${WORK}/static-summary
mkdir -p "${SUMMARY}/app/config"
jq '.station_conf.routerid = "AABBCCDDEEFF0011" | .station_conf.whitelist_netids = ["0x000013", "0x000014"] | .station_conf.gps = "/dev/ttyS0"' \
    "${HERE}/runner/station.corecell.conf" > "${SUMMARY}/app/config/station.conf"
printf 'Authorization: Bearer fixture-key\r\n' > "${SUMMARY}/app/config/tc.key"
run_in "" "" "${SUMMARY}" -e WHITELIST_NETIDS=0x00AAAA -- start --render
[[ ${STATUS} -eq 0 ]] || fail_output "static summary render exited ${STATUS}"
expect "${OUTPUT}" "static summary" "NetIDs:        0x000013,0x000014" "GPS Device:    /dev/ttyS0" \
    "WARNING: WHITELIST_NETIDS is ignored, static station.conf in use"
reject "${OUTPUT}" "static summary" "0x00AAAA"

section "whitelists"
WL=${WORK}/whitelists
mkdir -p "${WL}/tmp"
SEVENTEEN=$( seq -s, 1 17 )
SIXTEEN=$( seq -s, 1 16 )
{
    echo "netids17|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_NETIDS=${SEVENTEEN}"
    echo "ouis17|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_OUIS=${SEVENTEEN}"
    echo "badhex|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_NETIDS=0xZZ"
    echo "leadingzero|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_NETIDS=000013"
    echo "toobig|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_OUIS=0x1000000"
    echo "sixteen|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_NETIDS=${SIXTEEN} WHITELIST_OUIS=${SIXTEEN}"
    echo "formats|start --render|MODEL=RAK5146 TC_KEY=x WHITELIST_NETIDS=0x000013,19"
} > "${WL}/tmp/cases.txt"
batch "${WORK}/whitelists-out" "${WL}"
W=${WORK}/whitelists-out
for CASE in netids17:"WHITELIST_NETIDS has 17 entries, the limit is 16" \
            ouis17:"WHITELIST_OUIS has 17 entries, the limit is 16" \
            badhex:"WHITELIST_NETIDS entry '0xZZ' is not a valid 3-byte number" \
            leadingzero:"WHITELIST_NETIDS entry '000013' is not a valid 3-byte number (use 0x000013 for hex)" \
            toobig:"WHITELIST_OUIS entry '0x1000000' is not a valid 3-byte number"; do
    [[ "$( case_status "${W}" "${CASE%%:*}" )" != "0" ]] || fail "whitelist case ${CASE%%:*} was accepted"
    expect "$( case_output "${W}" "${CASE%%:*}" )" "whitelist output (${CASE%%:*})" "ERROR: ${CASE#*:}"
done
same "$( case_status "${W}" sixteen )" "0" "exit status with 16 entries"
same "$( jq_file "${W}/sixteen/config/station.conf" '.station_conf.whitelist_netids | length' )" "16" "NetIDs written"
same "$( case_status "${W}" formats )" "0" "exit status for 0x000013,19"
same "$( jq_file "${W}/formats/config/station.conf" '.station_conf.whitelist_netids | join(",")' )" \
    "0x000013,0x000013" "NetIDs written for 0x000013,19"

section "station with 20 NetIDs and 20 OUIs in station.conf"
STATION_WL=${WORK}/station-whitelist
mkdir -p "${STATION_WL}/app/config"
jq --argjson ids "$( seq 1 20 | jq -R 'tonumber | "0x" + ("000000" + (. | tostring)) [-6:]' | jq -s . )" \
    '.station_conf.routerid = "AABBCCDDEEFF0011" | .SX1302_conf.device = "spi:/dev/spidev0.0"
     | .station_conf.whitelist_netids = $ids | .station_conf.whitelist_ouis = $ids' \
    "${HERE}/runner/station.corecell.conf" > "${STATION_WL}/app/config/station.conf"
echo "wss://tts-mock:8887" > "${STATION_WL}/app/config/tc.uri"
printf 'Authorization: Bearer fixture-key\r\n' > "${STATION_WL}/app/config/tc.key"
run_station "" "${STATION_WL}" "Connecting to INFOS" "${STAND_IN[@]}" -- start
expect "${OUTPUT}" "station log" "whitelist_netids: 20 entries, kept 16, ignored 4" \
    "whitelist_ouis: 20 entries, kept 16, ignored 4"
sleep 10
same "$( docker inspect -f '{{.State.Running}}' "${RUNNING}" )" "true" "station running 10 s after reading 20+20 whitelist entries"
stop_station

# -----------------------------------------------------------------------------
# Deprecated aliases
# -----------------------------------------------------------------------------

section "deprecated aliases"
AL=${WORK}/aliases
mkdir -p "${AL}/tmp"
{
    echo "spi_old|start --render|MODEL=RAK5146 TC_KEY=x LORAGW_SPI=/dev/spidev1.0"
    echo "spi_new|start --render|MODEL=RAK5146 TC_KEY=x DEVICE=/dev/spidev1.0"
    echo "reset_old|start --render|MODEL=RAK5146 TC_KEY=x GW_RESET_GPIO=22"
    echo "reset_new|start --render|MODEL=RAK5146 TC_KEY=x RESET_GPIO=22"
    echo "enable_old|start --render|MODEL=RAK5146 TC_KEY=x GW_POWER_EN_GPIO=23"
    echo "enable_new|start --render|MODEL=RAK5146 TC_KEY=x POWER_EN_GPIO=23"
    echo "region_old|start --render|MODEL=RAK5146 TC_KEY=x TTN_REGION=au1"
    echo "region_new|start --render|MODEL=RAK5146 TC_KEY=x TTS_REGION=au1"
} > "${AL}/tmp/cases.txt"
batch "${WORK}/aliases-out" "${AL}" --mac-address "${MAC_A}"
A=${WORK}/aliases-out
for PAIR in spi reset enable region; do
    same "$( case_status "${A}" "${PAIR}_old" )" "0" "exit status for the old ${PAIR} variable"
    diff -r --no-dereference "${A}/${PAIR}_old/config" "${A}/${PAIR}_new/config" || fail "the old ${PAIR} variable gives a different configuration"
done
same "$( jq_file "${A}/spi_old/config/station.conf" .SX1302_conf.device )" "spi:/dev/spidev1.0" "device from LORAGW_SPI"
expect "$( < "${A}/reset_old/config/reset.sh" )" "reset script from GW_RESET_GPIO" 'RESET_GPIO="22"'
expect "$( < "${A}/enable_old/config/reset.sh" )" "reset script from GW_POWER_EN_GPIO" 'POWER_EN_GPIO="23"'
same "$( < "${A}/region_old/config/tc.uri" )" "wss://au1.cloud.thethings.network:8887" "tc.uri from TTN_REGION"

# -----------------------------------------------------------------------------
# Image contents
# -----------------------------------------------------------------------------

section "runtime commands"
# Every external command the runner scripts and reset scripts call
RUNTIME_COMMANDS="bash jq socat curl gpioset gpiodetect ip perl timeout awk sed grep head tr ls cp chmod ln mkdir sleep readlink dirname stty"
run_in "" "" "" -- bash -c "for c in ${RUNTIME_COMMANDS}; do command -v \$c > /dev/null || echo \"missing: \$c\"; done; echo checked"
expect "${OUTPUT}" "runtime command check" "checked"
reject "${OUTPUT}" "runtime command check" "missing:"

section "version banner, build record and labels"
label() { docker image inspect "${IMAGE}" --format "{{ index .Config.Labels \"$1\" }}"; }
run_in "" "" "" -e MODEL=RAK5146 -e TC_KEY=x -- bash -c 'cat /app/build-info; echo "IMAGE_VERSION=${IMAGE_VERSION}"; start --render'
info() { sed -n "s/^$1=//p" <<< "${OUTPUT}" | head -1; }
STATION_GROUP=$( sed -n '/Station built with:/,/chip_id tools built with:/p' <<< "${OUTPUT}" )
CHIPID_GROUP=$( sed -n '/chip_id tools built with:/,/------/p' <<< "${OUTPUT}" )
expect "${STATION_GROUP}" "banner (station)" "basicstation v$( info basicstation )" \
    "lora_gateway v$( info station.lora_gateway )" "sx1302_hal v$( info station.sx1302_hal )" \
    "picoGW_hal v$( info station.picoGW_hal )"
expect "${CHIPID_GROUP}" "banner (chip_id)" "sx1302_hal v$( info chip_id.sx1302_hal )" \
    "picoGW_hal v$( info chip_id.picoGW_hal )"
same "$( label com.xoseperez.basicstation.upstream-version )" "$( info basicstation )" "Basic Station version label"
same "$( label com.xoseperez.basicstation.chip-id.sx1302-hal-version )" "$( info chip_id.sx1302_hal )" "chip_id sx1302_hal label"
same "$( label com.xoseperez.basicstation.chip-id.picogw-hal-version )" "$( info chip_id.picoGW_hal )" "chip_id picoGW_hal label"
same "$( label org.opencontainers.image.version )" "$( info IMAGE_VERSION )" "image version label"
expect "${OUTPUT}" "banner" "Packet Forwarder Container $( info IMAGE_VERSION )"
echo "build record: $( grep -E '^[a-z_.]+=' <<< "${OUTPUT}" | grep -v IMAGE_VERSION | tr '\n' ' ' )"

# -----------------------------------------------------------------------------
# NET mode
# -----------------------------------------------------------------------------

section "NET mode link"
# A TCP echo server stands in for the serial-over-TCP bridge (ser2net).
# Discovery probes /dev/ttyV0 with chip_id, which fails against an echo server
# and closes the device; plain opens and closes follow. The link must then still
# be there, and pass data, for station to open it.
create --network-alias net-echo -- socat TCP-LISTEN:3333,fork,reuseaddr EXEC:cat
docker start "${CONTAINER}" > /dev/null
# shellcheck disable=SC2016
run_in "" "" "" -- timeout 90 bash -c '
    # The link is a symlink to a pty; opening it read-only never creates a file
    # in its place if it is gone
    alive() { [ -L /dev/ttyV0 ] && [ -c "$(readlink -f /dev/ttyV0)" ]; }
    wait_link() { for i in $(seq 1 20); do alive && return 0; sleep 0.5; done; return 1; }
    source /app/common.sh
    DEVICE=net-echo:3333 create_network_link
    wait_link || { echo "no link"; exit 1; }
    timeout 15 /app/artifacts/corecell/chip_id -u -d /dev/ttyV0 > /dev/null 2>&1
    echo "probed"
    for n in 1 2; do
        wait_link || { echo "link gone after the chip_id probe"; exit 1; }
        exec 3< /dev/ttyV0; exec 3<&-
    done
    sleep 2
    wait_link || { echo "link gone after open and close"; exit 1; }
    echo "link alive"
    stty -F /dev/ttyV0 raw -echo
    ( timeout 5 head -c 4 < /dev/ttyV0 > /tmp/got ) &
    READER=$!
    sleep 0.5
    printf ping > /dev/ttyV0
    wait "${READER}"
    echo "echo: $(cat /tmp/got)"
    exit 0'
printf '%s\n' "${OUTPUT}"
expect "${OUTPUT}" "NET link check" "link alive" "echo: ping"
[[ ${STATUS} -eq 0 ]] || fail_output "the NET link check exited ${STATUS}"

section "done"
echo "   total: ${SECONDS}s"
