#!/usr/bin/env bash

# Works out the image version and tags for a release tag. The release workflow
# appends the output to $GITHUB_ENV; it runs the same in any clone:
#
#   .github/release-versions.sh v2.9.0
#
# Release tags are this repository's versions: v<major>.<minor>.<patch>. Only
# NAME=VALUE lines go to stdout, because $GITHUB_ENV accepts nothing else and a
# stray line would fail the job; the summary and every error go to stderr,
# where the log shows them.

set -euo pipefail

cd "$( dirname "$0" )/.."

TAG=${1:-}

if ! [[ "${TAG}" =~ ^v([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    echo "::error::Tag '${TAG}' does not match v<major>.<minor>.<patch>" >&2
    exit 1
fi
MAJOR="v${BASH_REMATCH[1]}"
MINOR="${MAJOR}.${BASH_REMATCH[2]}"

# Image tags keep the v prefix the earlier releases used, so v2 and latest keep
# moving for anyone who pinned them. Rebuilding an older release must not move
# the floating tags back, so they are only added for the newest tag.
NEWEST=$( git tag -l | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n1 )
IMAGE_TAGS="${TAG}"
if [[ "${TAG}" == "${NEWEST}" ]]; then
    IMAGE_TAGS="${TAG},${MINOR},${MAJOR},latest"
fi

echo "VERSION=${TAG#v}"
echo "IMAGE_TAGS=${IMAGE_TAGS}"
echo "REVISION=$( git rev-parse HEAD )"
echo "Image tags: ${IMAGE_TAGS//,/ }" >&2
