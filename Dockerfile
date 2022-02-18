ARG ARCH
ARG TAG
ARG VERSION
ARG BUILD_DATE
ARG REMOTE_TAG
ARG VARIANT

# Builder image
FROM balenalib/${ARCH}-debian:buster-build as builder
ARG ARCH
ARG REMOTE_TAG
ARG VARIANT

# Switch to working directory for our app
WORKDIR /app

# Checkout and compile remote code
COPY builder/* ./
RUN chmod +x *.sh
RUN ARCH=${ARCH} REMOTE_TAG=${REMOTE_TAG} VARIANT=${VARIANT} ./build.sh

# Runner image
FROM balenalib/${ARCH}-debian:buster-run as runner
ARG ARCH
ARG TAG
ARG VERSION
ARG BUILD_DATE
ARG REMOTE_TAG
ARG VARIANT

# Image metadata
LABEL maintainer="Xose Pérez <xose.perez@gmail.com>"
LABEL authors="Jose Marcelino, Marc Pous, Xose Pérez and Semtech"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.build-date=${BUILD_DATE}
LABEL org.label-schema.name="LoRaWAN Basics™ Station"
LABEL org.label-schema.version="${VERSION} based on ${REMOTE_TAG}-${VARIANT}"
LABEL org.label-schema.description="LoRaWAN gateway with Basics™ Station Packet Forward protocol"
LABEL org.label-schema.vcs-type="Git"
LABEL org.label-schema.vcs-url="https://github.com/xoseperez/basicstation"
LABEL org.label-schema.vcs-ref=${TAG}
LABEL org.label-schema.arch=${ARCH}
LABEL org.label-schema.license="BSD License 2.0"

# Install required runtime packages
RUN install_packages jq vim

# Switch to working directory for our app
WORKDIR /app

# Copy fles from builder and repo
COPY --from=builder /app/basicstation/build-rpi-${VARIANT} ./design-v2
COPY --from=builder /app/basicstation/build-corecell-${VARIANT} ./design-corecell
COPY --from=builder /app/basicstation/build-linuxpico-${VARIANT} ./design-picocell
COPY runner/* ./
RUN chmod +x *.sh

# Launch our binary on container startup.
CMD ["bash", "start.sh"]
