variable "TAG" { default = "" }
variable "BUILD_DATE" { default = "" }
variable "REGISTRY" { default = "docker.io/xoseperez/basicstation" }

group "default" {
    targets = ["armv7hf", "aarch64"]
}

target "armv7hf" {
    tags = ["${REGISTRY}:armv7hf"]
    args = {
        "ARCH" = "armv7hf",
        "TAG" = "${TAG}",
        "BUILD_DATE" = "${BUILD_DATE}"
    }
    platforms = ["linux/arm/v7"]
}

target "aarch64" {
    tags = ["${REGISTRY}:aarch64"]
    args = {
        "ARCH" = "aarch64",
        "TAG" = "${TAG}",
        "BUILD_DATE" = "${BUILD_DATE}"
    }
    platforms = ["linux/arm64"]
}
