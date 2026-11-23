# Changelog

## 3.0.0 (unreleased)

* **Breaking for images built on top of this one:** the base image is now Alpine Linux 3.24 (musl) instead of Debian 12, so use `apk` instead of `apt-get`, and glibc binaries don't run
* libgpiod 2.x resets SPI concentrators on Linux 5.10 or newer; older kernels use sysfs, and `USE_LIBGPIOD=1` on them is an error
* `perl` is no longer in the image
* Much smaller image: the Alpine base, and only the packages the scripts use

## 2.9.0 (2026-11-23)

* Images are built by a GitHub Actions workflow for `linux/amd64`, `linux/arm64` and `linux/arm/v7`
* `find_concentrator` and `gateway_eui` reset SPI concentrators again
* Autoprovisioning improves (registers the EUI station uses, properly reports a failure, keeps `TTS_PERSONAL_KEY` out of the process list)
* `TTS_USERNAME` and `TTS_PERSONAL_KEY` can also be given as the `tts.username` and `tts.personal_key` secrets
* `GATEWAY_EUI_SOURCE=<interface>` picks that interface again
* `USE_LIBGPIOD=0` selects sysfs again
* Certificate chains in `TC_TRUST`, `TC_CRT`, `CUPS_TRUST`, `CUPS_CRT` and their secret files keep every certificate
* The default trust is the image's system CA bundle, refreshed with every build, instead of a bundled copy from 2022
* Whitelists: more than 16 entries, or an invalid entry, stop the service with an error
* A `station.conf` without `routerid` or `device` no longer shows `NULL`
* Without a GPIO chip, the reset script warns instead of silently not resetting the concentrator
* Probing a tty concentrator no longer changes how SPI concentrators are probed afterwards
* `INTERFACE=NET`: the link to ser2net survives the concentrator probes and container restarts
* `INTERFACE=NET`: the service stops when the link to ser2net drops
* `INTERFACE=NET`: downlinks fixed
* `docker-compose.yml`: `POWER_EN_LOGIC` example, GPIO chip comments, `RESET_GPIO_CHIP`/`ENABLE_GPIO_CHIP`, `VARIANT: stdn`, option numbering
* Smaller image: `sudo`, `gnupg`, `dirmngr`, `udev`, `vim`, `procps`, `inetutils-ping` and `netbase` are no longer installed, and the build stage installs only what the build needs
* The upstream patches are split into one change per patch, each with a note on why it is needed; the built code is unchanged

## 2.8.6 (2025-10-28)

* Defaults to use LIBGPIOd (USE_LIBGPIOD=1)

## 2.8.5 (2025-09-15)

* Remove dependency from balenalib images
* Remove balena-specific options

## 2.8.4 (2024-08-27)

* Add options to disable LBT, duty-cycle and dwell-time limitations (development option only)
* Add support for GPS coordinates and PPS (required for class B beaconing)
* Force main process to run as PID 1

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
