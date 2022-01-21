#!/bin/bash

set -e
cd $(dirname $0)

REMOTE_TAG=${REMOTE_TAG:-42d4b9c} # This is release v2.0.5

# Clone 
if [[ ! -d basicstation ]]; then
    git clone https://github.com/lorabasics/basicstation basicstation
fi

# Chack out tag
cd basicstation
git checkout ${REMOTE_TAG}

# Copy new files
mv ../V2.1.0-corecell.patch deps/lgw1302/

# Apply patches
if [ -f ../${REMOTE_TAG}.patch ]; then
    echo "Applying ${REMOTE_TAG}.patch ..."
    git apply ../${REMOTE_TAG}.patch
fi

# Build
make platform=rpi variant=std arch=${ARCH}
make platform=corecell variant=std arch=${ARCH}
