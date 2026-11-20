# Builds the image for all platforms:
#   docker buildx bake -f docker-bake.hcl
# For this machine only, loaded into the local Docker:
#   docker buildx bake -f docker-bake.hcl --load --set '*.platform=linux/amd64'

variable "REGISTRY" { default = "xoseperez/basicstation" }
# The Basic Station release the image packages. It is shown in the startup
# banner and in the image labels.
variable "BASICSTATION_VERSION" { default = "2.0.6" }
# The HALs this repository builds for the chip_id tools. Station builds its
# own HALs, at the versions its deps/ folder pins.
variable "SX1302_HAL_VERSION" { default = "2.1.0" }
variable "PICOGW_HAL_VERSION" { default = "0.2.3" }
variable "VARIANT" { default = "stdn" }
# This repository's version, shown in the startup banner and the labels
variable "VERSION" { default = "dev" }
# Comma-separated image tags, the release's own first. CI passes
# "vX.Y.Z,vX.Y,vX,latest" for the newest release and "vX.Y.Z" for an older one.
variable "IMAGE_TAGS" { default = "dev" }
variable "REVISION" { default = "" }

group "default" {
  targets = ["basicstation"]
}

target "basicstation" {
  context   = "."
  platforms = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags      = [for t in split(",", IMAGE_TAGS) : "${REGISTRY}:${t}" if t != ""]
  args = {
    BASICSTATION_VERSION = BASICSTATION_VERSION
    SX1302_HAL_VERSION   = SX1302_HAL_VERSION
    PICOGW_HAL_VERSION   = PICOGW_HAL_VERSION
    VARIANT              = VARIANT
    VERSION              = VERSION
  }
  labels = {
    "org.opencontainers.image.title"       = "LoRaWAN Basics Station"
    "org.opencontainers.image.description" = "LoRaWAN gateway with the Basics Station packet forwarder"
    "org.opencontainers.image.source"      = "https://github.com/xoseperez/basicstation-docker"
    "org.opencontainers.image.version"     = VERSION
    "org.opencontainers.image.revision"    = REVISION
    "org.opencontainers.image.licenses"    = "BSD-3-Clause"
    "com.xoseperez.basicstation.upstream-version"           = BASICSTATION_VERSION
    "com.xoseperez.basicstation.chip-id.sx1302-hal-version" = SX1302_HAL_VERSION
    "com.xoseperez.basicstation.chip-id.picogw-hal-version" = PICOGW_HAL_VERSION
  }
}
