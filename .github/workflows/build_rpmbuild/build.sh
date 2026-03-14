#!/bin/bash
set -euox pipefail

# Usage: Run from repo root with RPM version and GitHub token
#   .github/workflows/build_rpmbuild/build.sh <GH_TOKEN>
#   .github/workflows/build_rpmbuild/build.sh ghp_xxxx

docker build \
    -f .github/workflows/build_rpmbuild/Dockerfile \
    --build-arg GH_TOKEN="${1}" \
    -t rpmbuild-static \
    .

CONTAINER_ID=$(docker create rpmbuild-static)
docker cp "${CONTAINER_ID}:/tmp/artifacts/." .
docker rm "${CONTAINER_ID}"
