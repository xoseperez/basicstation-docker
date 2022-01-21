# Changelog

## 1.1.0 (2022-01-21)

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
