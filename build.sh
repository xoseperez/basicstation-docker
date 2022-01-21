#!/bin/bash

# Uses docker buildx and https://github.com/estesp/manifest-tool

export TAG=$(git rev-parse --short HEAD)
export VERSION=$(git describe --abbrev=0 --tags)
export MAJOR=$(git describe --abbrev=0 --tags | cut -d '.' -f1)
export REGISTRY=${REGISTRY:-"xoseperez/basicstation"}
export BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ACTION=$@
time docker buildx bake $ACTION

if [ "$ACTION" == "--push" ]; then

    MANIFEST=manifest.yaml
    cat > $MANIFEST << EOL
image: $REGISTRY:$TAG
tags: ['$VERSION', '$MAJOR', 'latest']
manifests:
  - image: $REGISTRY:aarch64
    platform:
      architecture: arm64
      os: linux  
  - image: $REGISTRY:armv7hf
    platform:
      architecture: arm
      os: linux  
EOL

    manifest-tool push from-spec $MANIFEST
    rm $MANIFEST

fi
