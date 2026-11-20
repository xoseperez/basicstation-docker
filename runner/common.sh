# shellcheck shell=bash
# The variables set here are read by the scripts that source this file.
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# Helpers shared by start, find_concentrator and gateway_eui. Sourced, not run.
#
# Only logic that is identical for every caller lives here. Defaults that
# differ between callers (reset pins, EUI order) stay in the callers and are
# passed in as arguments.
# -----------------------------------------------------------------------------

COMMON_DIR=$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------

COLOR_INFO="\e[32m" # green
COLOR_WARNING="\e[33m" # yellow
COLOR_ERROR="\e[31m" # red
COLOR_END="\e[0m"

# -----------------------------------------------------------------------------
# GPIO reset script
# -----------------------------------------------------------------------------

# Succeeds when the running kernel is Linux 5.10 or newer, the release that
# added the GPIO character device uAPI v2 that libgpiod 2 needs. The kernel is
# the host's, since containers share it. This goes by version only: an older
# vendor kernel with the uAPI backported still gets sysfs, which works there.
function gpio_uapi_v2 {

    local RELEASE
    RELEASE=$( uname -r )
    [[ "${RELEASE}" =~ ^([0-9]+)\.([0-9]+) ]] || return 1
    (( 10#${BASH_REMATCH[1]} > 5 || ( 10#${BASH_REMATCH[1]} == 5 && 10#${BASH_REMATCH[2]} >= 10 ) ))

}

# Chooses libgpiod or sysfs once; later calls keep the first answer.
# Unset, USE_LIBGPIOD is 1 when gpioset exists and the kernel has GPIO uAPI v2,
# and GPIO_ACCESS_NOTE says why when it isn't. Set by the user, it wins, except
# that USE_LIBGPIOD=1 on a kernel without uAPI v2 is an error: every gpioset
# call would fail and the concentrator would start without a reset.
function resolve_use_libgpiod {

    [[ -n "${GPIO_ACCESS_RESOLVED}" ]] && return 0

    GPIO_ACCESS_NOTE=""
    if [[ -z "${USE_LIBGPIOD}" ]]; then
        if ! command -v gpioset >/dev/null 2>&1; then
            USE_LIBGPIOD=0
            GPIO_ACCESS_NOTE="gpioset not found"
        elif ! gpio_uapi_v2; then
            USE_LIBGPIOD=0
            GPIO_ACCESS_NOTE="Linux $( uname -r ) has no GPIO uAPI v2"
        else
            USE_LIBGPIOD=1
        fi
    elif [[ "${USE_LIBGPIOD}" -eq 1 ]]; then
        if ! gpio_uapi_v2; then
            echo -e "${COLOR_ERROR}ERROR: USE_LIBGPIOD=1 needs Linux 5.10 or newer, and this host runs $( uname -r ). Unset USE_LIBGPIOD to use sysfs.${COLOR_END}"
            return 1
        fi
    else
        GPIO_ACCESS_NOTE="USE_LIBGPIOD=${USE_LIBGPIOD}"
    fi
    GPIO_ACCESS_RESOLVED=1

}

# render_reset_file TARGET RESET_GPIO POWER_EN_GPIO POWER_EN_LOGIC
# Writes the reset script for the concentrator. Each placeholder is filled from
# the arguments or the GPIO chip variables, and the script fails rather than
# write a file with a placeholder left in it: gpioset would get the literal
# text, fail quietly, and the concentrator would never be reset.
function render_reset_file {

    local TARGET=$1
    local TEMPLATE CONTENT

    resolve_use_libgpiod || return 1

    # The first pinctrl chip is the SoC's GPIO block on a Raspberry Pi
    if [[ "${USE_LIBGPIOD}" -eq 1 ]]; then
        GPIO_CHIP=${GPIO_CHIP:-$( gpiodetect 2>/dev/null | grep pinctrl | head -1 | awk '{print $1}' )}
        TEMPLATE="${COMMON_DIR}/reset.sh.gpiod"
    else
        TEMPLATE="${COMMON_DIR}/reset.sh.legacy"
    fi

    # Separate gpiochips for reset and enable, each falling back to GPIO_CHIP
    RESET_GPIO_CHIP=${RESET_GPIO_CHIP:-${GPIO_CHIP}}
    ENABLE_GPIO_CHIP=${ENABLE_GPIO_CHIP:-${GPIO_CHIP}}

    # Quoted replacements, so characters such as & are taken literally
    CONTENT=$( < "${TEMPLATE}" )
    CONTENT=${CONTENT//\{\{RESET_GPIO_CHIP\}\}/"${RESET_GPIO_CHIP}"}
    CONTENT=${CONTENT//\{\{ENABLE_GPIO_CHIP\}\}/"${ENABLE_GPIO_CHIP}"}
    CONTENT=${CONTENT//\{\{RESET_GPIO\}\}/"$2"}
    CONTENT=${CONTENT//\{\{POWER_EN_GPIO\}\}/"$3"}
    CONTENT=${CONTENT//\{\{POWER_EN_LOGIC\}\}/"$4"}

    if [[ "${CONTENT}" == *"{{"* ]]; then
        echo -e "${COLOR_ERROR}ERROR: ${TEMPLATE} has a placeholder this script does not fill${COLOR_END}"
        return 1
    fi

    printf '%s\n' "${CONTENT}" > "${TARGET}"
    chmod +x "${TARGET}"

}

# -----------------------------------------------------------------------------
# Gateway EUI from a network interface
# -----------------------------------------------------------------------------

# nic_eui NIC: prints the EUI-64 built from the NIC's MAC address
# (aa:bb:cc:dd:ee:ff -> AABBCCFFFEDDEEFF). Fails for a NIC that does not exist,
# or whose address is not a 6-byte MAC or is all zeros (loopback, tunnels).
function nic_eui {

    local MAC
    [[ -r "/sys/class/net/$1/address" ]] || return 1
    MAC=$( < "/sys/class/net/$1/address" )
    [[ "${MAC}" =~ ^([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})$ ]] || return 1
    [[ "${MAC}" == "00:00:00:00:00:00" ]] && return 1
    local EUI="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}FFFE${BASH_REMATCH[4]}${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
    echo "${EUI^^}"

}

# resolve_nic_eui REQUESTED: sets GATEWAY_EUI_SOURCE and GATEWAY_EUI.
# A requested NIC that exists is used. Otherwise ("manual", "chip", empty, or a
# NIC that isn't here) the first of eth0, wlan0, usb0 and eth1, then the NIC
# that received the most bytes. Loopback and NICs without a MAC never count:
# loopback would give the EUI 000000FFFE000000 on every gateway.
function resolve_nic_eui {

    local REQUESTED=$1
    local NIC DEVICE_PATH RX BEST="" BEST_RX=-1

    GATEWAY_EUI_SOURCE=""
    GATEWAY_EUI=""

    if [[ -n "${REQUESTED}" ]] && [[ "${REQUESTED}" != "manual" ]] && [[ "${REQUESTED}" != "chip" ]]; then
        if GATEWAY_EUI=$( nic_eui "${REQUESTED}" ); then
            GATEWAY_EUI_SOURCE=${REQUESTED}
            return 0
        fi
        echo -e "${COLOR_WARNING}WARNING: GATEWAY_EUI_SOURCE is '${REQUESTED}', but there is no such interface with a MAC address. Using the default order instead.${COLOR_END}"
    fi

    for NIC in eth0 wlan0 usb0 eth1; do
        if GATEWAY_EUI=$( nic_eui "${NIC}" ); then
            GATEWAY_EUI_SOURCE=${NIC}
            return 0
        fi
    done

    for DEVICE_PATH in /sys/class/net/*; do
        NIC=${DEVICE_PATH##*/}
        [[ "${NIC}" == "lo" ]] && continue
        nic_eui "${NIC}" >/dev/null || continue
        [[ -r "${DEVICE_PATH}/statistics/rx_bytes" ]] || continue
        RX=$( < "${DEVICE_PATH}/statistics/rx_bytes" )
        [[ "${RX}" =~ ^[0-9]+$ ]] || continue
        if (( RX > BEST_RX )); then
            BEST=${NIC}
            BEST_RX=${RX}
        fi
    done

    if [[ -n "${BEST}" ]]; then
        GATEWAY_EUI_SOURCE=${BEST}
        GATEWAY_EUI=$( nic_eui "${BEST}" )
        return 0
    fi

    GATEWAY_EUI=""
    return 1

}

# -----------------------------------------------------------------------------
# Network concentrator (INTERFACE=NET)
# -----------------------------------------------------------------------------

# wait_for_device DEVICE SECONDS: waits until DEVICE is a character device,
# following the symlink a NET mode link uses
function wait_for_device {

    local TRIES
    for (( TRIES = 0; TRIES < $2 * 2; TRIES++ )); do
        [[ -c "$( readlink -f "$1" )" ]] && return 0
        sleep 0.5
    done
    return 1

}

# Links /dev/ttyV0 to the TCP serial bridge at DEVICE (host:port), by default
# port 3333 on the default gateway, points DEVICE at the pty, and waits for it.
#
# socat ends the link as soon as the program using the pty closes it. chip_id
# closes it after every probe, so the link was gone before station could open
# it. A reader that never closes it keeps the link up across probes. If socat
# still ends (the TCP connection drops), the loop starts it again.
function create_network_link {

    NETLINK=${DEVICE:-$( ip route | awk '/default/ { print $3 ":3333" }' )}
    INTERFACE="USB"
    DEVICE="/dev/ttyV0"

    (
        while :; do
            socat "pty,link=${DEVICE},waitslave" "tcp:${NETLINK}" &
            SOCAT_PID=$!
            if wait_for_device "${DEVICE}" 10; then
                exec 9< "${DEVICE}"
            fi
            wait "${SOCAT_PID}"
            exec 9<&-
            sleep 1
        done
    ) &

    wait_for_device "${DEVICE}" 10 || echo -e "${COLOR_WARNING}WARNING: ${DEVICE} did not appear, is ${NETLINK} reachable?${COLOR_END}"

}
