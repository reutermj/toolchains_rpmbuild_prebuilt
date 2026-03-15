# Dockerfile for locally reproducing the RPM build + install validation tests.
#
# Usage:
#   docker build -f .github/workflows/test/Dockerfile \
#     --build-arg RPM_VERSION=6.0 \
#     .
#
# Supported RPM_VERSION values: 6.0 (default), 4.20, 4.19

FROM fedora:latest

RUN dnf install -y --setopt=install_weak_deps=False \
  rpm \
  git \
  && dnf clean all

ARG RPM_VERSION=6.0

WORKDIR /src
COPY . .

RUN ./bazel test //tests/rpm:validate_rpm --repo_env=rpmbuild_version=${RPM_VERSION}
