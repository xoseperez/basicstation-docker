# Built through docker-bake.hcl, which passes the versions below and builds
# every platform. For this machine only:
#   docker buildx bake -f docker-bake.hcl --load --set '*.platform=linux/amd64'

ARG BASICSTATION_VERSION=2.0.6
ARG SX1302_HAL_VERSION=2.1.0
ARG PICOGW_HAL_VERSION=0.2.3
ARG VARIANT=stdn
ARG VERSION=dev

# Builder image
FROM debian:bookworm-slim AS builder
ARG TARGETPLATFORM
ARG BASICSTATION_VERSION
ARG SX1302_HAL_VERSION
ARG PICOGW_HAL_VERSION
ARG VARIANT

# Install required development packages
COPY builder/install_packages /usr/sbin/
RUN chmod 0755 /usr/sbin/install_packages
RUN install_packages \
    git \
    ca-certificates \
    build-essential

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
FROM debian:bookworm-slim AS runner
ARG VARIANT
ARG VERSION

# Install utility
COPY builder/install_packages /usr/sbin/
RUN chmod 0755 /usr/sbin/install_packages

# Runtime packages: the commands the runner scripts call, and the system CA
# bundle used as the default trust
RUN install_packages \
    bash \
    jq \
    socat \
    curl \
    gpiod \
    iproute2 \
    ca-certificates

# Image metadata (OCI labels come from docker-bake.hcl)
LABEL maintainer="Xose Pérez <xose.perez@gmail.com>"
LABEL authors="Jose Marcelino, Marc Pous, Xose Pérez and Semtech"

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

# Launch our binary on container startup.
CMD ["start"]
