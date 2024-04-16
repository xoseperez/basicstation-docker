#!/bin/bash

# Uses docker buildx and https://github.com/estesp/manifest-tool

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------

PUSH=0
TARGETS=()
MANIFEST_TOOL=manifest-tool
MANIFEST_FILE=manifest.yaml

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------

# Check we have buildx extension for docker
if ! docker buildx version &> /dev/null; then
  echo "ERROR: docker or docker buildx extension are not installed"
  exit 1
fi

  # Check we have the manifest modifier tool
if ! hash ${MANIFEST_TOOL} &> /dev/null; then
  echo "ERROR: ${MANIFEST_TOOL} could not be found!"
    exit 1
  fi

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  if [[ "${1,,}" == "--push" ]]; then
    PUSH=1
  else
    TARGETS+=( "$1" )
  fi
  shift
done

# -----------------------------------------------------------------------------
# Export settings for builder
# -----------------------------------------------------------------------------

TAG=$( git rev-parse --short HEAD )
VERSION=$( git describe --abbrev=0 --tags )
MAJOR=$( git describe --abbrev=0 --tags | cut -d '.' -f1 )
BUILD_DATE=$( date -u +"%Y-%m-%dT%H:%M:%SZ" )
REGISTRY=${REGISTRY:-"xoseperez/basicstation"}
REMOTE_TAG=${REMOTE_TAG:-"v2.0.6"}
VARIANT=${VARIANT:-"stdn"}

export TAG
export VERSION
export MAJOR
export BUILD_DATE
export REGISTRY
export REMOTE_TAG
export VARIANT

# -----------------------------------------------------------------------------
# Ask for confirmation if pushing
# -----------------------------------------------------------------------------

if [[ ${PUSH} -eq 1 ]]; then

  # Ask confirmation if pushing to a registry
  echo "Pushing image into ${REGISTRY}"
  echo "Tags: ${MAJOR}, ${VERSION}, ${TAG}, latest"
  read -r -p "Are you sure? [y/N] " RESPONSE
  if [[ ! "${RESPONSE}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Cancelled"
    exit 1
  fi

fi

# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

if [[ ${PUSH} -eq 1 ]]; then
  time docker buildx bake --push "${TARGETS[@]}"
else
  time docker buildx bake "${TARGETS[@]}"
fi

# -----------------------------------------------------------------------------
# Merge individual archs into the same tags
# -----------------------------------------------------------------------------

if [[ ${PUSH} -eq 1 ]] && [[ ${#TARGETS[@]} -eq 0 ]]; then

    cat > ${MANIFEST_FILE} << EOL
image: ${REGISTRY}:${TAG}
tags: ['${VERSION}', '${MAJOR}', 'latest']
manifests:
  - image: ${REGISTRY}:aarch64-latest
    platform:
      architecture: arm64
      os: linux  
  - image: ${REGISTRY}:armv7hf-latest
    platform:
      architecture: arm
      os: linux  
  - image: ${REGISTRY}:amd64-latest
    platform:
      architecture: amd64
      os: linux  
EOL

    ${MANIFEST_TOOL} push from-spec ${MANIFEST_FILE}
    rm ${MANIFEST_FILE}

fi
