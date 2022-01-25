#!/usr/bin/env bash

WAIT_GPIO() {
    sleep 0.01
}

RESET_GPIO=${RESET_GPIO:-17}
POWER_EN_GPIO=${POWER_EN_GPIO:-0}
POWER_EN_LOGIC=${POWER_EN_LOGIC:-1}

# Enable gateway
if [[ $POWER_EN_GPIO -ne 0 ]]; then
    echo "Concentrator enabled through GPIO$POWER_EN_GPIO"
    if [[ -d /sys/class/gpio/gpio$POWER_EN_GPIO ]]; then
        echo $POWER_EN_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
    fi
    echo $POWER_EN_GPIO > /sys/class/gpio/export; WAIT_GPIO
    echo out > /sys/class/gpio/gpio$POWER_EN_GPIO/direction; WAIT_GPIO
    echo $POWER_EN_LOGIC > /sys/class/gpio/gpio$POWER_EN_GPIO/value; WAIT_GPIO
    echo $POWER_EN_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
fi

# Reset gateway
if [[ $RESET_GPIO -ne 0 ]]; then
    echo "Concentrator reset through GPIO$RESET_GPIO"
    if [[ -d /sys/class/gpio/gpio$RESET_GPIO ]]; then
        echo $RESET_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
    fi
    echo $RESET_GPIO > /sys/class/gpio/export; WAIT_GPIO
    echo out > /sys/class/gpio/gpio$RESET_GPIO/direction; WAIT_GPIO
    echo 0 > /sys/class/gpio/gpio$RESET_GPIO/value; WAIT_GPIO
    echo 1 > /sys/class/gpio/gpio$RESET_GPIO/value; WAIT_GPIO
    echo 0 > /sys/class/gpio/gpio$RESET_GPIO/value; WAIT_GPIO
    echo $RESET_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
fi

exit 0
