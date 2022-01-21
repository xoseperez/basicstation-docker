#!/usr/bin/env bash

WAIT_GPIO() {
    sleep 0.01
}

GW_POWER_EN_GPIO=${GW_POWER_EN_GPIO:-0}
GW_RESET_GPIO=${GW_RESET_GPIO:-17}

# Enable gateway
if [ $GW_POWER_EN_GPIO -ne 0 ]
then
    echo "Concentrator enabled through GPIO$GW_POWER_EN_GPIO"
    if [ -d /sys/class/gpio/gpio$GW_POWER_EN_GPIO ]
    then
        echo $GW_POWER_EN_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
    fi
    echo $GW_POWER_EN_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
    echo $GW_POWER_EN_GPIO > /sys/class/gpio/export; WAIT_GPIO
    echo out > /sys/class/gpio/gpio$GW_POWER_EN_GPIO/direction; WAIT_GPIO
    echo 1 > /sys/class/gpio/gpio$GW_POWER_EN_GPIO/value; WAIT_GPIO
    echo $GW_POWER_EN_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
fi

# Reset gateway
echo "Concentrator reset through GPIO$GW_RESET_GPIO"
if [ -d /sys/class/gpio/gpio$GW_RESET_GPIO ]
then
    echo $GW_RESET_GPIO > /sys/class/gpio/unexport; WAIT_GPIO
fi
echo $GW_RESET_GPIO > /sys/class/gpio/export; WAIT_GPIO
echo out > /sys/class/gpio/gpio$GW_RESET_GPIO/direction; WAIT_GPIO
echo 0 > /sys/class/gpio/gpio$GW_RESET_GPIO/value; WAIT_GPIO
echo 1 > /sys/class/gpio/gpio$GW_RESET_GPIO/value; WAIT_GPIO
echo 0 > /sys/class/gpio/gpio$GW_RESET_GPIO/value; WAIT_GPIO
echo $GW_RESET_GPIO > /sys/class/gpio/unexport; WAIT_GPIO

exit 0