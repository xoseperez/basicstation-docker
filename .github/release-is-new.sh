#!/usr/bin/env bash

# Stops a release that would overwrite a published version, unless REPLACE is
# true:
#
#   .github/release-is-new.sh IMAGE REPLACE
#
# Only the registry's "not found" answer counts as "not published". Any other
# failure (registry unreachable, rate limit, authentication, malformed
# reference) stops the release as well: treating it as "not published" would
# let the push overwrite a version after a passing registry error. If buildx
# ever words "not found" differently, the release stops and the log shows the
# new wording.

set -uo pipefail

IMAGE=$1
REPLACE=${2:-false}

if [[ "${REPLACE}" == "true" ]]; then
    echo "replace set, not checking whether ${IMAGE} is published"
    exit 0
fi

if ERROR=$( docker buildx imagetools inspect "${IMAGE}" 2>&1 > /dev/null ); then
    echo "::error::${IMAGE} is already published. To rebuild it, run this by hand with 'replace' ticked."
    exit 1
fi

if [[ "${ERROR##*$'\n'}" == *": not found" ]]; then
    echo "${IMAGE} is not published yet"
    exit 0
fi

echo "::error::cannot check whether ${IMAGE} is published: ${ERROR}"
exit 1
