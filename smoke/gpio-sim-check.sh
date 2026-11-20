#!/usr/bin/env bash

# Runs the image's reset script against a simulated GPIO chip, with the image's
# real libgpiod gpioset. The smoke test's stub gpioset only sees arguments;
# this checks what the stub can't:
# - each call holds its line for about 100 ms and then exits;
# - the line has the requested value while it is held;
# - gpiodetect output still starts with the chip name, which the scripts parse.
#
# The level after gpioset exits isn't checked. The line is released then, and
# a simulated chip's released state says nothing about a real board's.
#
#   smoke/gpio-sim-check.sh IMAGE
#
# Needs the gpio-sim kernel module and root for its configfs setup (sudo is
# used when not root). amd64 only: qemu-user does not translate the GPIO
# character device ioctls, so it can't run under emulation.

set -euo pipefail

IMAGE=$1
SUDO=""
[[ $( id -u ) -eq 0 ]] || SUDO=sudo

# Lines driven by the reset script, and the values each call should set
ENABLE=20
RESET="6,17"
EXPECTED="20=1 6=0 6=1 6=0 17=0 17=1 17=0"
MIN_MS=95
MAX_MS=150

fail() { echo "FAIL: $*" >&2; exit 1; }

${SUDO} modprobe gpio-sim || fail "the gpio-sim kernel module could not be loaded"

CFG=/sys/kernel/config/gpio-sim/smoke-$$
cleanup() {
    if [[ -d "${CFG}" ]]; then
        echo 0 | ${SUDO} tee "${CFG}/live" > /dev/null || true
        ${SUDO} rmdir "${CFG}/gpio-bank0" "${CFG}" || true
    fi
}
trap cleanup EXIT

${SUDO} mkdir "${CFG}" "${CFG}/gpio-bank0"
echo 32 | ${SUDO} tee "${CFG}/gpio-bank0/num_lines" > /dev/null
echo 1 | ${SUDO} tee "${CFG}/live" > /dev/null
CHIP=$( < "${CFG}/gpio-bank0/chip_name" )
SIM=/sys/devices/platform/$( < "${CFG}/dev_name" )/${CHIP}
[[ -c "/dev/${CHIP}" ]] || fail "/dev/${CHIP} was not created"
echo "simulated chip: ${CHIP} (${SIM})"

# The shim logs each call's arguments, the value read from the simulated line
# 50 ms into the hold, and how long the real gpioset ran.
# shellcheck disable=SC2016
SHIM='#!/bin/sh
LINE=$( for A in "$@"; do case "$A" in *=*) echo "${A%%=*}";; esac; done )
VALUE=$( for A in "$@"; do case "$A" in *=*) echo "${A#*=}";; esac; done )
T0=$( date +%s%N )
/usr/bin/gpioset "$@" &
PID=$!
sleep 0.05
HELD=$( cat "'"${SIM}"'/sim_gpio${LINE}/value" )
wait "${PID}"
RC=$?
T1=$( date +%s%N )
echo "${LINE}=${VALUE} held=${HELD} ms=$(( (T1 - T0) / 1000000 )) rc=${RC}" >> /tmp/gpio-sim.log
'

OUTPUT=$( docker run --rm --device "/dev/${CHIP}" \
    -e MODEL=RAK5146 -e TC_KEY=x -e GPIO_CHIP="${CHIP}" \
    -e RESET_GPIO="${RESET}" -e POWER_EN_GPIO="${ENABLE}" -e POWER_EN_LOGIC=1 \
    -e SHIM="${SHIM}" "${IMAGE}" bash -c '
        printf "%s" "${SHIM}" > /tmp/gpioset && chmod +x /tmp/gpioset
        echo "gpiodetect: $( gpiodetect | grep -F "${GPIO_CHIP}" | awk "{print \$1}" )"
        start --render > /dev/null 2>&1 || { echo "start --render failed"; exit 1; }
        PATH=/tmp:${PATH} bash /app/config/reset.sh
        cat /tmp/gpio-sim.log' 2>&1 ) || fail "the container failed: ${OUTPUT}"
printf '%s\n' "${OUTPUT}"

grep -qx "gpiodetect: ${CHIP}" <<< "${OUTPUT}" || fail "gpiodetect output did not start with the chip name"

CALLS=$( grep -E '^[0-9]+=[01] held=' <<< "${OUTPUT}" ) || fail "no gpioset call was logged"
[[ "$( awk '{print $1}' <<< "${CALLS}" | tr '\n' ' ' )" == "${EXPECTED} " ]] \
    || fail "calls were $( awk '{print $1}' <<< "${CALLS}" | tr '\n' ' ' ), expected ${EXPECTED}"
while read -r SET HELD MS RC; do
    [[ "${RC}" == "rc=0" ]] || fail "gpioset ${SET} exited ${RC#rc=}"
    [[ "${HELD#held=}" == "${SET#*=}" ]] || fail "line ${SET%%=*} read ${HELD#held=} while held, expected ${SET#*=}"
    MS=${MS#ms=}
    (( MS >= MIN_MS && MS <= MAX_MS )) || fail "gpioset ${SET} held for ${MS} ms, expected ${MIN_MS}-${MAX_MS}"
done <<< "${CALLS}"

echo "gpio-sim check passed: $( wc -l <<< "${CALLS}" ) calls, each held its value for ${MIN_MS}-${MAX_MS} ms"
