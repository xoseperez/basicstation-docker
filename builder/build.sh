#!/bin/bash

set -e
cd $(dirname $0)

ARCH=${ARCH:-armv7hf}
REMOTE_TAG=${REMOTE_TAG:-"v2.0.5"}
VARIANT=${VARIANT:-std}

# Clone 
if [[ ! -d basicstation ]]; then
    git clone https://github.com/lorabasics/basicstation basicstation
fi

# Chack out tag
cd basicstation
git checkout ${REMOTE_TAG}

# Apply patches
if [ -f ../${REMOTE_TAG}.patch ]; then
    echo "Applying ${REMOTE_TAG}.patch ..."
    git apply ../${REMOTE_TAG}.patch
fi

# Build
make platform=rpi variant=${VARIANT} arch=${ARCH}
make platform=corecell variant=${VARIANT} arch=${ARCH}
