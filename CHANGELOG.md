# Changelog

## 2.8.3 (2024-04-16)

* Support for RAKwireless RAK5166 and RAK5167 M.2 concentrators
* Support for Dragino PG1302 MiniPCIe concentrator
* Remove support for ARMv6 arch
* Move base images to bookworm releases

## 2.8.2 (2024-04-03)

* Option to provide certs and keys using docker secrets

## 2.8.1 (2024-03-15)

* Support for auto-discover for Picocell concentrators
* General clean up of the code
* Option to filter uplinks and join requests using whitelists

## 2.8.0 (2024-02-29)

* Auto-discover concentrator for corecell
* Option to get the EUI from a corecell or picocell chip ID
* Refactor gateway_eui and find_concentrator utilities
* Deprecation notices for `GATEWAY_EUI_NIC`, `GW_RESET_GPIO`, `GW_POWER_EN_GPIO` and `GW_POWER_EN_LOGIC`
* Support for remote concentrators via ser2net
* Support for MacOS host (using ser2net)

## 2.7.0 (2024-02-05)

* Support for Raspberry Pi 5

## 2.6.2 (2023-11-13)

* Use 2MHz as default LORAGW_SPI_SPEED for SX1308 concentrators (#10)
* Fix upstream bug in parsing region_id (#11, https://github.com/lorabasics/basicstation/issues/162)

## 2.6.1 (2023-02-17)

* Option to define the radio clock source for the concentrator using CLKSRC
* Fix certificate cleaning, was failing for RSA certs like the ones used by AWS LNS

## 2.6.0 (2023-01-05)

* Support for client certificate/key based connections (like ChirpStack does)

## 2.5.0 (2022-11-18)

* Support for ARMv6 architectures (Raspberry PI 1, Raspberry Pi Zero), this includes RAK7246.

## 2.4.3 (2022-11-01)

* Revert to using `sysfs` as default way to manage the GPIO. Management via `libgpiod` is still available by setting `USE_GPIOLIB` to 1

## 2.4.2 (2022-10-11)

* Fix GW_RESET_GPIO not working (#8)

## 2.4.1 (2022-09-21)

* Fix wrong URL for The Things Cloud server

## 2.4.0 (2022-09-19)

* Autoprovision gateway in The Things Stack (TTI/TTN)
* Improve logs readibility in docker

## 2.3.5 (2022-08-01)

* Force CUPS mode using USE_CUPS for compatibility with Actility ThingPark

## 2.3.4 (2022-06-17)

* Provide pre-built reset script to basicstatin process

## 2.3.3 (2022-05-30)

* Fix compatibility issue with USB Bridge firmware prior to 1.0.0 (RAK2287 USB)

## 2.3.2 (2022-05-19)

* Log parsing tools
* Calculate and report GATEWAY_EUI before TC_KEY missing error
* Highlight summary

## 2.3.1 (2022-03-08)

* Using gpiod instead of /sys/class/gpio to reset concentrator
* Fix Balena build (BALENA_API_KEY available)

## 2.3.0 (2022-02-18)

* Support for PicoCell concentrator designs (such as MikroTik R11e-LoRa8/9)
* INTERFACE takes precedence over DEVICE

## 2.2.1 (2022-02-05)

* Support for CUPS protocol

## 2.2.0 (2022-02-04)

* Based on BasicStation 2.0.6, lora_gateway 5.0.1 (SX1301) and sx1302_hal 2.1.0 (SX1302 & SX1303)
* Support for SX1302/SX1303 USB concentrators
* Support for amd64 architecture (run your basicstation gateway from your PC)
* Support for multiple radios enabled by default
* Option to specify the SPI bus speed, default values depending on concentrator
* Pre-cached certificates

## 2.1.1 (2022-02-02)

* Improvements in the build process
* Changed the way the concentrator is reset to allow multiple radios on the same device
* Balena compatibility fixes
* Support to build different variants (default to "std")
* Enable PPS on corecell concentrators
* Accept RAK WisGate Developer gateways models as MODEL
* Show concentrator type on debug log

## 2.1.0 (2022-01-26)

 * Option to define the GATEWAY_EUI of the device manually
 * Advanced configuration mode
 * support for multiple radios on the same device (either with ~~a single service or~~ multiple services)
 * Support for RAK833-USB/SPI module
 
## 2.0.0 (2022-01-21)

 * Cloning original basicstation repo instead of forking it
 * Unify running configuration & scripts
 * Reset repo to get rid of upstream commits/branches/tags/... (yes, I know)

## 1.0.1 (2022-01-20)

 * Support for SX1303 concentrators using sx_1302_hal v2.0.1
 * Building multiple arch images into the same tags
 * Check SPI enabled
 * Remove TTNv2 support
 * Custom script to retrieve Gateway EUI

## 1.0.0 (2021-06-02)

* Based on BasicStation 2.0.5, lora_gateway 5.0.1 (SX1301) and sx1302_hal 1.0.5 (SX1302)
* Compatible with SX1301 and SX1302 concentrators using SPI interface
* Docker image for armv7hf (32 bits) and aarch64 (64 bits) architectures
