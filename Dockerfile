# Built through docker-bake.hcl, which passes the versions below and builds
# every platform. For this machine only:
#   docker buildx bake -f docker-bake.hcl --load --set '*.platform=linux/amd64'

# Both stages are built on this base. To bump it, change it here, then run the
# smoke test, the GPIO timing check and the hardware checks, and update the
# end-of-support date in the README.
ARG BASE_IMAGE=alpine:3.24
ARG BASICSTATION_VERSION=2.0.6
ARG SX1302_HAL_VERSION=2.1.0
ARG PICOGW_HAL_VERSION=0.2.3
ARG VARIANT=stdn
ARG VERSION=dev

# Builder image
FROM ${BASE_IMAGE} AS builder
ARG TARGETPLATFORM
ARG BASICSTATION_VERSION
ARG SX1302_HAL_VERSION
ARG PICOGW_HAL_VERSION
ARG VARIANT

# Development packages. linux-headers provides the spidev and i2c headers the
# HALs include; the GNU tools keep the build scripts on the behaviour they were
# written for.
RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    bash \
    ca-certificates \
    coreutils \
    findutils \
    sed \
    grep

# Switch to working directory for our app
WORKDIR /app

# Checkout and compile remote code. The build runs on the target platform
# (emulated for ARM), and station's makefiles name the toolchain by
# architecture, so the platform is mapped to their names.
COPY builder/build ./
COPY builder/patches ./patches
RUN chmod +x build
RUN case "${TARGETPLATFORM}" in \
        linux/amd64)  ARCH=amd64 ;; \
        linux/arm64)  ARCH=aarch64 ;; \
        linux/arm/v7) ARCH=armv7hf ;; \
        *) echo "Unsupported platform: '${TARGETPLATFORM}'"; exit 1 ;; \
    esac && \
    ARCH=${ARCH} \
    BASICSTATION_VERSION=${BASICSTATION_VERSION} \
    SX1302_HAL_VERSION=${SX1302_HAL_VERSION} \
    PICOGW_HAL_VERSION=${PICOGW_HAL_VERSION} \
    VARIANT=${VARIANT} \
    ./build

# Runner image
FROM ${BASE_IMAGE} AS runner
# A global ARG only reaches the FROM lines; the label and ENV below need it
# declared again in this stage, or they come out empty.
ARG BASE_IMAGE
ARG VARIANT
ARG VERSION

# Runtime packages: the commands the runner scripts call, and the system CA
# bundle used as the default trust. The GNU tools replace BusyBox's, whose sed,
# grep, awk and timeout lack options the scripts use.
RUN apk add --no-cache \
    bash \
    jq \
    socat \
    curl \
    libgpiod \
    iproute2 \
    ca-certificates \
    sed \
    grep \
    gawk \
    coreutils \
    findutils

# Image metadata (OCI labels come from docker-bake.hcl)
LABEL maintainer="Xose Pérez <xose.perez@gmail.com>"
LABEL authors="Jose Marcelino, Marc Pous, Xose Pérez and Semtech"
LABEL org.opencontainers.image.base.name="docker.io/library/${BASE_IMAGE}"

# Switch to working directory for our app
WORKDIR /app

# Copy files from builder and repo
RUN mkdir ./artifacts
COPY --from=builder /app/basicstation/build-rpi-${VARIANT}/bin ./artifacts/v2
COPY --from=builder /app/basicstation/build-corecell-${VARIANT}/bin ./artifacts/corecell
COPY --from=builder /app/basicstation/build-linuxpico-${VARIANT}/bin ./artifacts/picocell
COPY --from=builder /app/build-info ./build-info
COPY runner/* ./
RUN chmod +x start gateway_eui find_concentrator

# Add application folder to path
ENV PATH="${PATH}:/app"
ENV IMAGE_VERSION=${VERSION}
ENV BASE_IMAGE=${BASE_IMAGE}

# Launch our binary on container startup.
CMD ["start"]
